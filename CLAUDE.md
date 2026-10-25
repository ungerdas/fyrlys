# Fyrlys-appen – arbeidsnotater for Claude

Egen app for Fyrlys, Pål-Eriks IPTV-spiller: Flutter med media_kit (mpv) som avspiller, for Windows,
Android og Android TV (senere macOS, Linux og iOS). Den kommer **i tillegg til** Docker-versjonen
(nettside + server med ffmpeg) i det private repoet `ungerdas/peagstreams`, som kjører på LenovoTorrentPC
(http://192.168.50.18:8766). Ikke bland inn endringer der herfra. Dette repoet er tenkt offentlig, så
ingen detaljer om hjemmenettet hans i koden (eksempeladresser som 192.168.1.10 er greit).

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
  prøve på Windows-PC-en (peagpc), telefon eller TV.
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
- `ui/login_page.dart`, `ui/home_page.dart` (sidemeny ≥ 900 px, ellers nedtrekksliste), `ui/channel_card.dart`,
  `ui/player_page.dart` (media_kit `Video` uten egne kontroller + eget lag: kanalbytte, lydspor/undertekster,
  fullskjerm via window_manager, tastatur og fjernkontroll; nye forsøk ved brudd/fast bilde, tre per minutt).
- `theme.dart` – fargene fra nettversjonen («Fyrlys om natta» / «Nordisk lys»).
- Tester i `test/`: navn, Xtream-kilden, Fyrlys-kilden (med MockClient) og widget-tester med en falsk kilde.

## Status
- 25.10.2026: v0.1 skrevet. Ikke prøvd på ekte enheter ennå.
- Ideer senere: tilbakespoling i mpv-bufferet, TV-guide, bilde-i-bilde på Android, filmer/serier,
  kanalnummer med tall, signering av exe/APK, Play Store, iOS/macOS.
