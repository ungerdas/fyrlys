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
- **Versjoner** (Pål-Erik 26.10): hver oppdatering han får (hver push som gir et nytt testbygg), får neste
  patch-versjon i pubspec: 2.1.2 (26.10, det som først het 2.0.3), så 2.1.3, 2.1.4 … Øk før hver push som bygges.
  Feiler bygget i CI, har han ikke fått noe, og rettelsen beholder nummeret. Det er versjonen vi snakker om, ikke
  byggnummeret (det brukes bare av oppdateringen). Skriv avsnittet i `CHANGELOG.md`. GitHub-release (workflowen)
  bare når han ber om det. Hver push oppdaterer releasen
  `testbygg` (jobben `testbygg`: taggen flyttes, filene byttes med `--clobber`, navnet «Fyrlys X · bygg N (sha)»
  settes sist, siste commits som notater), og Fyrlys på Windows oppdaterer seg selv derfra via Fyrlys-serveren.
  Privat repo: 2000 gratis Actions-minutter i måneden på gratiskontoen, og hver push bruker rundt 25 (Windows
  teller dobbelt). Bruk `[skip ci]` når en endring bare gjelder notater. Versjon, byggnummer
  og commit står nederst i menyen (`--dart-define` FYRLYS_VERSION/BUILD/COMMIT/REPO, `lib/build_info.dart`).
- Release: oppdater `version` i pubspec.yaml, push, og start
  `gh workflow run build.yml --repo ungerdas/fyrlys -f release=vX.Y.Z`. Jobben `release` lager taggen og en
  GitHub-release med `Fyrlys-vX.Y.Z-windows.zip` og APK-er per ABI (v0.x som forhåndsutgivelse). Tagger kan
  ikke pushes fra Claude-økta, og git/refs-API-et er stengt, men workflowen kan startes. En tag `v*` som
  Pål-Erik lager selv, gir samme resultat. Bruk `[skip ci]` i commit-meldingen når et bygg bare er bortkastet.
  Teksten i releasen er avsnittet `## vX.Y.Z` i `CHANGELOG.md` (skriv det før releasen). Byggnummeret
  (`--build-number`, også versionCode på Android) er `github.run_number`.
- Android-signering: med hemmelighetene `ANDROID_KEYSTORE_B64`/`ANDROID_KEYSTORE_PASSWORD`/`ANDROID_KEY_ALIAS`
  signeres APK-ene på nytt med `apksigner` etter bygget (README forklarer hvordan nøkkelen lages); uten dem har
  hvert bygg en tilfeldig debug-nøkkel. Hemmeligheter kan ikke leses eller settes fra Claude-økta (Actions-API-et
  er stengt i proxyen), så Pål-Erik må legge dem inn selv.

## Arkitektur (`lib/`)
- `core/source.dart` – `TvSource`: kilde til kanaler, EPG, strømadresser og favoritter.
  - `core/xtream_source.dart` – rett mot leverandøren (Xtream Codes, port av `xtream.py`): `player_api.php`,
    User-Agent som VLC, strøm `/live/<bruker>/<passord>/<id>.m3u8` og `.ts` som reserve, EPG i base64.
  - `core/fyrlys_source.dart` – mot Fyrlys-serveren: `/api/streams/info` (ffmpeg?), `/api/xtream/status`,
    `/api/xtream/categories`, `/api/xtream/streams` (sider à 120), `/api/xtream/epg`, logoer via
    `/api/xtream/img?u=`. TV **direkte** (2.1.4, Pål-Erik: «det skal ikke gjennom serveren»), når `/api/streams/info`
    har `direct: true`: `GET /api/live/<id>/direct?c=<klient>` spørres først (409 `busy` → «Ta over»; `&force=1` bare
    da), så spiller mpv `/api/xtream/hls/<id>.m3u8?c=` (reserve `/api/xtream/file/live/<id>.ts?c=`): leverandørens
    strøm uendret via serverens mellomstasjon (passordet blir på serveren), og `stillWatching` gjentar `direct?c=`
    hvert 10. s (`PlayTarget.keepAlive`; 409 = tatt over). Eldre servere: ffmpeg som før (`GET
    /api/live/<id>/index.m3u8?c=`, så samme adresse uten force, tilbakespoling på serveren).
    `POST /api/live/<id>/stop?c=` ved kanalbytte/lukking. Favoritter som endringer
    (`PUT /api/streams/favs` med `op`), delt med nettsiden.
  - Filmer og serier (`core/vod.dart`: modellene, `pageOf`/`catalogOf` for filtrering, sortering og sider à 120,
    `episodeCode`, `ratingText`): Fyrlys-serveren gjør det selv (`/api/xtream/categories?kind=vod|series`,
    `/api/xtream/streams?kind=&cat=&q=&sort=&start=`, `/api/xtream/vod?id=`, `/api/xtream/series?id=`, filen via
    `/api/xtream/file/vod|series/<id>.<ext>` med Range), uavhengig av `FYRLYS_VOD` (som bare gjelder nettsiden).
    Rett mot leverandøren hentes hele lista (`get_vod_streams`/`get_series`, 30 min) og filtreres i appen;
    filene er `/movie/` og `/series/<bruker>/<passord>/<id>.<ext>`. Filmer og serier går utenom «Ta over» og
    seertellingen på serveren.
- `core/cache.dart` – det som tas vare på mellom gangene (2.1.3): `ListCache` (`FileListCache` i
  `getApplicationSupportDirectory()/lister`, én JSON per kilde med nøkkelen `kind|label`; `MemoryListCache` i testene)
  og `ImageStore` (bildene i `getApplicationCacheDirectory()/bilder`, filnavn `stableHash(url)`, fornyes etter 14 dager,
  det gamle brukes når nettet feiler, 404 huskes i 10 min, `prune()` ved start holder det under 300 MB). Settes opp i
  `main.dart` (path_provider); uten dem (testene) hentes alt som før.
- `core/session.dart` – tilstanden (ChangeNotifier): innlogging (lagres i shared_preferences, også
  Xtream-passordet – vurder flutter_secure_storage senere), lister, EPG-mellomlager (5 min, 4 om gangen),
  `epg(id, limit:)` (en lengre liste fra guiden brukes også av kortene; `cleanEpg` i `models.dart` slår sammen
  doble programmer og kutter overlapp, som `clean_epg` på serveren), favoritter (lokalt for Xtream, på
  serveren for Fyrlys-server, i kø), «sist sett», lys/mørk, og «fortsett der du
  slapp» (`resume` i shared_preferences: «film:<id>»/«episode:<id>» → [sekunder, lengde, når], maks 300;
  `resumeAt` gir null under 30 s og over 95 %, `watched` gir streken). Språkene (`languages`/`saveLanguages`,
  `lang_audio`/`lang_subs` i shared_preferences; `LanguagePrefs` og kodene i `core/languages.dart`). Lista fra
  `listCache` vises med en gang (`_startLists`), `load` skriver den nye; `_prefetchEpg` henter programinfo for 12
  favoritter og 8 sist sett når lista er klar og når favorittene kommer fra serveren.
- `ui/login_page.dart`, `ui/home_page.dart` (TV/TV-guide/Filmer/Serier: SegmentedButton i toppen ≥ 900 px (ikoner ≥ 1200), ellers
  NavigationBar nederst; TV har sidemeny ≥ 900 px med ikoner, ellers nedtrekksliste; søket gjelder fanen du er på,
  på Hjem alle kanalene), `ui/channel_card.dart` (`showNext`: også det som kommer etterpå).
- `ui/start_view.dart` – Hjem (filteret `home`, valgt når appen starter, 26.10 for 2.0.3; Pål-Erik ville ha vekt på TV,
  ikke filmer/serier): hilsen og dato/klokke, `LastWatchedCard` (siste i «sist sett», nå/etterpå, «Se videre»), eller
  velkomst første gang; favoritter (12, med nå og etterpå), resten av «sist sett» bortover, dine kategorier (ellers de
  16 første) som knapper, og «Fortsett å se» lite nederst.
- Kanalnummer (`ui/channel_number.dart`: `digitOf`, `NumberBadge`; `channelByNumber` i `models.dart`): tallene samles
  i 1,4 s (OK/Enter går straks), lista du ser fra først og så alle kanalene, som `numGo` på nettsiden. I spilleren via
  `_onKey` (også fra kanallista, ikke i søket), på TV-siden og i guiden via `HardwareKeyboard`-handler i
  `home_page.dart` (bare når siden er øverst og søket ikke har fokus).
- `ui/net_image.dart` – `NetImage` (alle nettbilder: logoer, plakater, bakgrunner, episodebilder): `StoredImage` via
  `ImageStore`, `ResizeImage` til `decodeWidth` × skjermtetthet, tones inn (ikke når det alt var i minnet).
- `ui/motion.dart` – `fadeRoute` (begge spillerne), `SmoothSwitch` (AnimatedSwitcher: fanene i `home_page.dart` og
  listene/Hjem på TV, nøkkel `start`/`liste:<filter>`), `Lift` (kort som løftes ved fokus/hover: kanalkort, plakater,
  «Fortsett å se», sist sett). Tester må `pumpAndSettle` etter fane-/listebytter (to barn under overgangen).
- `ui/language_dialog.dart` – «Språk for lyd og undertekster» (FilterChips i den rekkefølgen du velger, «Av» for
  undertekster) og `TracksButton`, sporvalget i begge spillerne (henter sporene asynkront så det som faktisk spilles
  er huket av; «Foretrukne språk …» nederst gjelder straks). TV via ffmpeg på serveren (eldre servere) har bare første
  lydspor og ingen undertekster (`-map 0:a:0 -sn`); direkte (2.1.4) har alt.
- `ui/guide_view.dart` – TV-guiden, som på nettsiden: 6 timer fra halvtimen før denne halvtimen (`guideStart`),
  5 px/min (4 på smale skjermer), «nå»-strek, «Til nå», kategori (★ Favorittkanaler / Alle / dine kategorier
  først; huskes i `guide_cat`) og søket i toppen. Kanalnavnene er en egen liste til venstre som rulles sammen med
  programmene (to ScrollControllere som følger hverandre); programmene ligger i en vannrett rulling, og titler
  som begynte før det synlige, flyttes inn (ListenableBuilder på den vannrette). Hver rad henter
  `session.epg(id, limit: 14)` etter 150 ms framme (`epgCached` gir det som alt er hentet uten å vente). Trykk på
  det som går nå eller på kanalnavnet = spill; senere/tidligere program = info med «Se kanalen». På PC kan
  guiden dras med musa, og programmene har verktøytips.
- `ui/vod_browser.dart` (plakater i rutenett, kategori, sortering, sider hentes når du er 30 fra slutten, søk
  med 350 ms pause; «Fortsett å se» øverst når det ikke er søk/kategori: `Session.continueItems` (`continue` i
  shared_preferences, `ContinueItem` i `vod.dart`, maks 50), oppdatert av filmspilleren via `VodPlayItem.continueAs`:
  filmer til de er sett (> 95 %), serier med episoden du er på, eller den neste når en er sett ferdig;
  `playContinue` spiller rett, serier via `seriesInfo`), `ui/vod_detail_page.dart` (`_Hero`: bakgrunnsbilde fra
  `backdrop_path` eller uskarp plakat, tonet mot bakgrunnen, plakat, tittel uten merker (`cleanTitle`: «[PRE]» blir
  merke, «[2026]» år), merker for år/sjanger/spilletid (`runtimeText`)/vurdering/alder/land/kvalitet
  (`MediaTech.badges` fra `video`/`audio` i get_vod_info); film: spill av / fortsett / fra begynnelsen og «Mer fra
  <kategori>»; serie: sesonger og episoder i rutenett (to kolonner på brede skjermer), `episodeTitle` fjerner
  «Serie - S01E01 - », bakgrunnsbildet med nummeret når episoden mangler bilde; `Poster`), `ui/vod_player_page.dart` (egen spiller for filer: tidslinje, ±10 s,
  neste/forrige episode, volum, spor, fullskjerm; lagrer hvor du er hvert 10. s og når du går ut, starter med
  `Media(start:)`, går til neste episode 1,5 s etter slutten).
- `ui/player_page.dart` – som spilleren på nettsiden (alltid mørk): bildet med kontroller og programinfo under,
  kanallista (`ui/side_list.dart`: lista du kom fra / ★ Favoritter, søk) til høyre fra 860 px, ellers under.
  Fullskjerm = bare bildet (window_manager på PC, immersive på Android; et maksimert vindu gjøres vanlig først,
  ellers lar window_manager 0.5.x tittellinja stå og bunnen havner bak oppgavelinja; vindusanimasjonene er av
  mens det skjer, via `DwmSetWindowAttribute` i `ui/window_effects.dart` (FFI, bare Windows)), kanallista over bildet med C; telefon på
  tvers = fullskjerm. Bildet ligger under en GlobalKey, så det flyttes mellom oppsettene uten å starte på nytt.
  Volum (glidebryter på PC, musehjulet over bildet, lagres i Session), ⇄/Backspace, tastatur og fjernkontroll
  (OK = fullskjerm/kanalliste, → inn i lista, ← ut). Infoen viser oppløsning, kodek/hwdec/lyd (mpv-egenskaper)
  og hvor strømmen kommer fra. Nye forsøk ved brudd/fast bilde, tre per minutt. Kanalbytte (2.1.3): ↑/↓ setter
  `_pendingZap` (kanalinfoen viser den, programinfo via `session.epg`) og starter den etter 650 ms (`_commitZap`; OK
  straks, Esc avbryter); `_banner` nederst i bildet (`ValueKey('channel-banner')`) vises mens du blar, 4 s etter
  `_switchTo` og til den nye kanalen har startet (`_switching`), ikke ved første åpning, spoling eller nye forsøk;
  toppstripa i fullskjerm skjules imens. Den lille spinneren i banneret går til bildet starter: ingen
  `pumpAndSettle` i tester etter et kanalbytte (den falske avspilleren starter aldri). Telefon/TV: kanalen stoppes når
  appen legges bort (`paused`) og startes igjen ved `resumed`.
  Pause og tilbakespoling i appen selv (2.1.4, `PlayTarget.localShift`: direkte via serveren og rett mot leverandøren):
  `setup(live: true)` gir mpv `cache=yes`, `demuxer-seekable-cache=yes` og `cache-on-disk` i
  `<cache>/mpv` (`MpvPlayback.cacheDir`, ryddes ved start; 2000/1000 MiB bak/foran på PC, 600/300 på Android, mindre i
  minnet uten mappe). Vakta spør `liveCache()` (fra `demuxer-cache-state`: `reader-pts`, `cache-end`,
  `seekable-ranges`) hvert 2. s; «direkte» er det minste avspilleren har foran mens du ser direkte (`_liveAhead`,
  strømmen kommer i biter, derfor 15 s slakk i `_atLive`), bak direkte = foran − det. Spoling = `seekBy` (mpv
  `seek <s> relative`) i bufferet, uten å åpne på nytt. Ikke prøvd i ekte mpv.
  Tilbakespoling via Fyrlys-serveren med ffmpeg (eldre servere: `PlayTarget.timeshift` fra `timeshift_min` i
  `/api/streams/info`): ffmpegs HLS-demuxer kan ikke spole i en direktesending, så spillelista åpnes på nytt med
  `live_start_index=-N` (`change-list demuxer-lavf-o append`, så media_kits egne valg står). N regnes ut fra
  `#EXTINF` i spillelista (`TvSource.liveWindow`, `LiveWindow.at`; 3 fra slutten er «direkte»). Hvor langt bak du
  er = der du begynte + pausene (`package:clock`, så testene kan spole tida). Spillelista hentes hvert 15. s (10 s på
  pause, så serveren ikke stopper kanalen); 409 da = tatt over. Pause over 45 s åpnes på nytt der du var. Tidslinje,
  −10/+10 (samles i 450 ms), «DIREKTE» (trykk = direkte), ←, → (på PC og i fullskjerm; ellers inn i lista), L/End.
- `ui/playback.dart` – `Playback`: mpv via media_kit (`MpvPlayback`), en falsk i testene (`playbackFactory`
  byttes ut i testene for sider som lager avspilleren selv). Fullskjerm for begge spillerne:
  `WindowFullscreen` i `ui/window_effects.dart`. Språk: `setLanguages` setter `alang`/`slang` og
  `subs-with-matching-audio=no` når undertekstspråk er valgt; ved ny adresse settes `aid=auto` og `sid=auto`/`no`
  (et spor valgt for hånd står ellers i mpv til neste fil; samme adresse, f.eks. etter spoling, beholder det).
  `tracks()` leser `aid`/`sid` fra mpv (media_kit vet bare om spor valgt via `setAudioTrack`). Bildeundertekster
  (PGS/DVB) vises ikke: media_kit tegner tekstundertekster selv (`sub-visibility=no` uten libass).
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
  widget-tester for TV-siden og spilleren (`player_test.dart`, tilbakespoling i `timeshift_test.dart`) med falsk
  kilde og avspiller (`fakes.dart`),
  filmer og serier (`vod_source_test.dart`: kildene og lister; `vod_test.dart`: fanene, detaljsiden, spilleren,
  fortsett og neste episode), TV-guiden (`guide_test.dart`).

## Status
- 25.10.2026: v0.1 skrevet. Pål-Erik prøvde Windows-versjonen og savnet volumkontroll og spilleren slik den er
  på nettsiden før fullskjerm. Laget samme dag (spilleren som på nettsiden, volum, byggnummer i menyen), testet med
  widget-tester. Ikke prøvd på ekte enheter ennå; Android TV-navigasjon er helt uprøvd.
- 25.10.2026: automatisk oppdatering fra releasen `testbygg`. Pål-Erik ville beholde repoet privat, så den går via
  Fyrlys-serveren (`app/appupdate.py` i peagstreams, nøkkelen i `data/github.json` på serveren). Serverdelen er
  prøvd mot ekte GitHub, appdelen bare med tester. Første bygg med den må lastes ned for hånd.
  Nøkkelen ligger på serveren (virker, 25.10), og bygg 6 kjører på PC-en hans. Bygg 6 → 7 feilet: skriptet
  startet aldri (tom logg). `ProcessStartMode.detached` gir `DETACHED_PROCESS` (ingen konsoll) på Windows, og
  da kommer ikke Windows PowerShell i gang. Bygg 8 starter det i vanlig modus (Dart bruker da `CREATE_NO_WINDOW`:
  skjult konsoll), skriptet skriver `i-gang.txt` selv, og appen logger oppstarten i `oppdatering.log`.
  Bygg 7 → 8 måtte derfor også legges inn for hånd. Bygg 9 → 10 kom av seg selv (bekreftet av Pål-Erik 25.10):
  oppdateringen virker fra start til slutt. Fullskjerm fra maksimert vindu virker (bygg 9), animasjonen er
  fjernet i bygg 10 (ikke bekreftet ennå).
- 25.10.2026: Filmer og Serier i appen (ett bygg). Testet med kilde- og widget-tester, ikke med ekte avspilling:
  spoling, fortsett og neste episode i mpv, store lister fra leverandøren og fjernkontroll på Android TV er uprøvd.
- 25.10.2026: TV-guide i appen (Pål-Erik savnet den). Testet med widget-tester; ikke prøvd med ekte EPG eller
  fjernkontroll ennå.
- 25.10.2026: pause/tilbakespoling i direktesending og «Fortsett å se» (Pål-Eriks valg). Bare testet med tester;
  om `live_start_index` virker i mpv-en til media_kit, er ikke prøvd.
- 26.10.2026: Apple TV vurdert og lagt bort (Pål-Erik stoppet det). Flutter har ingen offisiell tvOS (bare
  flutter-tvos, uoffisiell) og media_kit finnes ikke for tvOS, så det ville blitt en egen Swift-app (AVPlayer for
  serverens HLS, MPVKit for MKV), bygget på GitHubs macOS-maskiner (~10x prisen per minutt) og lagt i TestFlight
  (krever betalt utviklerkonto). Enklere alternativ om det kommer opp igjen: M3U/XMLTV eller Xtream-API fra
  Fyrlys-serveren for en ferdig Apple TV-app.
- 26.10.2026: v2.0.0 (Pål-Eriks valg av nummer) etter en gjennomgang av koden med to uavhengige lesere. Rettet:
  passord i mpv-feil (`TvSource.redact`), kodede innloggingsdeler i Xtream-adressene, EPG-kø (150 ms før
  henting i kort og sideliste, nyeste først, feil huskes ikke), Filmer/Serier-løkke ved feil/tom side, én felles
  nedlasting av VOD-lister rett mot leverandøren (og 3 min tidsgrense for store lister), innlogging som ble
  hengende, IPv6, favoritter etter feil/ny innlogging, emoji i logo-forkortelsen, oppdateringsskriptet (venter på
  alle Fyrlys-prosesser, sikkerhetskopi og tilbakelegging), og i spilleren: OK på kortene, `_sideOpen` etter
  snuing, → ved direkte, `live_start_index` tilbake til 3 etter spoling, arbeid som startet rett før appen ble
  lagt bort.
- 26.10.2026: 2.1.2 (først levert som 2.0.3, bygg 24): Hjem (startsiden), kanalnummer med tall, språk for lyd og undertekster, «Spill av»/«Fortsett» på
  seriesiden. Testet med widget-tester; språkvalget i ekte mpv (koder, `subs-with-matching-audio` i media_kits
  libmpv) og tallene på en ekte fjernkontroll er ikke prøvd.
- 26.10.2026: 2.1.3, «mer smooth» (Pål-Eriks ønske, alle sju forslagene): lista og bildene på disk, programinfo
  ved start, kanalinfo ved bytte, rask blaing, overganger og fokus. Testet med tester; ikke prøvd på ekte enheter.
- 26.10.2026: 2.1.4: TV direkte (uendret strøm via serverens mellomstasjon, direkte-økter på serveren for «Ta over»
  og seere, se peagstreams) og pause/spoling i appens eget buffer (Pål-Eriks valg: «Appen husker selv»). Testet med
  tester; mpv-bufferet, `demuxer-cache-state` og spolingen i ekte mpv er ikke prøvd.
- Ideer senere: bilde-i-bilde på Android, bildeundertekster (DVB/PGS) med libass, signering av exe/APK, Play Store, iOS/macOS.
