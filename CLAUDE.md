# Fyrlys-appen – arbeidsnotater for Claude

Egen app for Fyrlys, Pål-Eriks IPTV-spiller: Flutter med media_kit (mpv) som avspiller, for Windows,
Android og Android TV (senere macOS, Linux og iOS). Den kommer **i tillegg til** Docker-versjonen
(nettside + server med ffmpeg) i det private repoet `ungerdas/peagstreams`, som kjører på hjemmeserveren hans.
Ikke bland inn endringer der herfra. Repoet er **privat** (Pål-Erik valgte 25.10 å beholde det slik), men hold
det fritt for detaljer om hjemmenettet hans, verken i koden, testene eller disse notatene, i tilfelle det blir
offentlig (eksempeladresser som 192.168.1.10 er greit).

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Flutter kan ikke kjøres i Claude-økta** (pub.dev og Googles nedlastinger er stengt). Skriv koden nøye,
  og la GitHub Actions analysere, teste og bygge: `gh run list --repo ungerdas/fyrlys`,
  `gh run view <id> --repo ungerdas/fyrlys --log-failed`, `gh run watch <id> --repo ungerdas/fyrlys`.
  Advarsler fra `flutter analyze` stopper bygget (info gjør ikke det), f.eks. ubrukte importer.
  Loggene og artefaktene kan **ikke** lastes ned herfra (de ligger i blob-lagring som er stengt). Når et steg
  feiler, legger workflowen slutten av loggen som merknad; les den med
  `gh api repos/ungerdas/fyrlys/check-runs/<jobb-id>/annotations` (jobb-id fra `gh run view <id> --json jobs`).
- Plattformmappene lages av `flutter create --org no.peag --project-name fyrlys` i hvert bygg. I repoet
  ligger bare det som er tilpasset, og det skrives ikke over: `android/app/src/main/AndroidManifest.xml`
  (INTERNET, cleartext, Android TV med leanback og banner), ikonene i `android/.../res/`
  (adaptivt ikon, `drawable-xhdpi/banner.png`), `windows/runner/resources/app_icon.ico`. Vindustittelen og
  filinfo på Windows settes med `sed` i workflowen. Ikonene er tegnet fra `fyrlys.svg` i nettversjonen.
- Videoavspilling kan ikke testes her: si tydelig hva som bare er testet med tester, og hva Pål-Erik må
  prøve på Windows-PC-en sin, telefon eller TV.
- Flutter- og media_kit-kildene kan hentes for å sjekke API-er (github.com er åpent for git):
  `git clone --depth 1 --branch stable --filter=blob:none --sparse https://github.com/flutter/flutter.git`
  og `git sparse-checkout set packages/flutter/lib packages/flutter_test/lib` (tilsvarende for media-kit/media-kit).
  `unnecessary_import` er en advarsel og stopper bygget; sjekk hva `material.dart` eksporterer.
- **Ikke lag ny versjon for hver rettelse** (Pål-Erik 25.10): push til `main`. Hver push oppdaterer releasen
  `testbygg` (jobben `testbygg`: taggen flyttes, filene byttes med `--clobber`, navnet «Fyrlys X · bygg N (sha)»
  settes sist, siste commits som notater), og Fyrlys på Windows oppdaterer seg selv derfra via Fyrlys-serveren.
  Privat repo: 2000 gratis Actions-minutter i måneden på gratiskontoen, og hver push bruker rundt 25 (Windows
  teller dobbelt). Bruk `[skip ci]` når en endring bare gjelder notater. Versjon, byggnummer
  og commit står nederst i menyen (`--dart-define` FYRLYS_VERSION/BUILD/COMMIT/REPO, `lib/build_info.dart`).
  Ny versjon når det virker.
- Release: oppdater `version` i pubspec.yaml, push, og start
  `gh workflow run build.yml --repo ungerdas/fyrlys -f release=vX.Y.Z`. Jobben `release` lager taggen og en
  GitHub-release med `Fyrlys-vX.Y.Z-windows.zip` og APK-er per ABI (v0.x som forhåndsutgivelse). Tagger kan
  ikke pushes fra Claude-økta, og git/refs-API-et er stengt, men workflowen kan startes. En tag `v*` som
  Pål-Erik lager selv, gir samme resultat. Bruk `[skip ci]` i commit-meldingen når et bygg bare er bortkastet.

## Arkitektur (`lib/`)
- `core/source.dart` – `TvSource`: kilde til kanaler, EPG, strømadresser og favoritter.
  - `core/xtream_source.dart` – rett mot leverandøren (Xtream Codes, port av `xtream.py`): `player_api.php`,
    User-Agent som VLC, strøm `/live/<bruker>/<passord>/<id>.m3u8` og `.ts` som reserve, EPG i base64.
  - `core/fyrlys_source.dart` – mot Fyrlys-serveren: `/api/streams/info` (ffmpeg?), `/api/xtream/status`,
    `/api/xtream/categories`, `/api/xtream/streams` (sider à 120), `/api/xtream/epg`, logoer via
    `/api/xtream/img?u=`. Strøm via ffmpeg på serveren: `GET /api/live/<id>/index.m3u8?c=<klient>` spørres
    først (409 `busy` → «Ta over»; `&force=1` **bare** i den spørringen), så spiller mpv samme adresse uten
    force. `POST /api/live/<id>/stop?c=` ved kanalbytte/lukking. Favoritter som endringer
    (`PUT /api/streams/favs` med `op`), delt med nettsiden.
- `core/session.dart` – tilstanden (ChangeNotifier): innlogging (lagres i shared_preferences, også
  Xtream-passordet – vurder flutter_secure_storage senere), lister, EPG-mellomlager (5 min, 4 om gangen),
  favoritter (lokalt for Xtream, på serveren for Fyrlys-server, i kø), «sist sett», lys/mørk.
- `ui/login_page.dart`, `ui/home_page.dart` (sidemeny ≥ 900 px, ellers nedtrekksliste), `ui/channel_card.dart`.
- `ui/player_page.dart` – som spilleren på nettsiden (alltid mørk): bildet med kontroller og programinfo under,
  kanallista (`ui/side_list.dart`: lista du kom fra / ★ Favoritter, søk) til høyre fra 860 px, ellers under.
  Fullskjerm = bare bildet (window_manager på PC, immersive på Android), kanallista over bildet med C; telefon på
  tvers = fullskjerm. Bildet ligger under en GlobalKey, så det flyttes mellom oppsettene uten å starte på nytt.
  Volum (glidebryter på PC, musehjulet over bildet, lagres i Session), ⇄/Backspace, tastatur og fjernkontroll
  (OK = fullskjerm/kanalliste, → inn i lista, ← ut). Infoen viser oppløsning, kodek/hwdec/lyd (mpv-egenskaper)
  og hvor strømmen kommer fra. Nye forsøk ved brudd/fast bilde, tre per minutt. Telefon/TV: kanalen stoppes når
  appen legges bort (`paused`) og startes igjen ved `resumed`.
- `ui/playback.dart` – `Playback`: mpv via media_kit (`MpvPlayback`), en falsk i testene.
- `core/updater.dart` – oppdatering fra releasen `testbygg` (bare Windows, bare bygg med byggnummer). Repoet er
  privat, så når appen er logget inn på en Fyrlys-server spør den `<server>/api/app/release` (serveren har en
  lesenøkkel i `data/github.json` og svarer i GitHubs form, med relative adresser `download/<fil>` som løses
  mot release-adressen); ellers `api.github.com/repos/<repo>/releases/tags/testbygg` (virker bare om repoet er
  offentlig). Sjekker etter `session.restore()` (+8 s) og hver 6. time, byggnummeret fra navnet,
  `-windows.zip` lastes ned til `%LOCALAPPDATA%\Fyrlys\oppdatering\bygg-N` (størrelsen sjekkes),
  så `klar.json`. Legges inn når appen lukkes (`didRequestAppExit` i `app.dart`), med «Start på nytt nå», eller
  før appen vises neste gang (`beforeStart` i `main.dart`). Et PowerShell-skript (bare ASCII) venter på prosessen,
  pakker ut og kopierer med robocopy, skriver `resultat.txt` (vises i banneret) og `oppdatering.log`.
  `klar.json` slettes før skriptet startes, og `i-gang.txt` (90 s) hindrer at appen starter midt i, så det
  aldri blir en løkke. Krever at Fyrlys-mappen er skrivbar (ikke Programfiler). Banner og «Se etter
  oppdateringer» i `home_page.dart`. Android oppdaterer seg ikke selv ennå (trenger fast signeringsnøkkel og
  installasjon av APK).
- `theme.dart` – fargene fra nettversjonen («Fyrlys om natta» / «Nordisk lys»).
- Tester i `test/`: navn, Xtream-kilden, Fyrlys-kilden (med MockClient), oppdateringen (`updater_test.dart`),
  widget-tester for TV-siden og spilleren (`player_test.dart`) med falsk kilde og avspiller (`fakes.dart`).

## Status
- 25.10.2026: v0.1 skrevet. Pål-Erik prøvde Windows-versjonen og savnet volumkontroll og spilleren slik den er
  på nettsiden før fullskjerm. Laget samme dag (spilleren som på nettsiden, volum, byggnummer i menyen), testet med
  widget-tester. Ikke prøvd på ekte enheter ennå; Android TV-navigasjon er helt uprøvd.
- 25.10.2026: automatisk oppdatering fra releasen `testbygg`. Pål-Erik ville beholde repoet privat, så den går via
  Fyrlys-serveren (`app/appupdate.py` i peagstreams, nøkkelen i `data/github.json` på serveren). Serverdelen er
  prøvd mot ekte GitHub, appdelen bare med tester. Første bygg med den må lastes ned for hånd.
  Nøkkelen ligger på serveren (virker, 25.10), og bygg 6 kjører på PC-en hans. Bygg 7 er laget for å prøve
  selve oppdateringen på Windows.
- Ideer senere: tilbakespoling i mpv-bufferet, TV-guide, bilde-i-bilde på Android, filmer/serier,
  kanalnummer med tall, signering av exe/APK, Play Store, iOS/macOS.
