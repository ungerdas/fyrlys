# Fyrlys-appen – arbeidsnotater for Claude

Egen app for Fyrlys, en IPTV-spiller: Flutter med media_kit (mpv) som avspiller, **bare for Windows**
(eieren 26.10: «vi kjører kun Windows, fjerner alt Linux og Android»; i 2.1.12 er Android-bygget, `android/`,
telefon-/TV-koden og et Linux-forsøk som aldri ble lagt ut, fjernet; det finnes i historikken). Den kommer **i tillegg til** Docker-versjonen
(nettside + server med ffmpeg) i et eget, privat repo.
Fra 2.1.6 (eieren 26.10: «Fyrlys server dropper vi») logger appen inn med M3U-lenke eller Xtream Codes og henter
alt rett fra leverandøren, og oppdateringene rett fra GitHub (fra 2.1.11 uten valg av oppdateringsserver); appen
bruker ikke Fyrlys-serveren til noe.
Ikke bland inn endringer der herfra. Repoet er **offentlig** (åpnet 26.10, så oppdateringene kommer rett fra
GitHub), og appen skal kunne deles med andre (eieren 26.10: «Fyrlys på windows er noe jeg vil dele, så der kan det ikke
være noe personlig»; appen og serverversjonen skal være helt adskilt). Hold appen, koden, testene, commit-meldingene,
filinfoen i exe-en og disse notatene fri for navn, hjemmenett, maskinnavn, leverandør, brukernavn, hemmeligheter og
e-postadresser (eksempeladresser som 192.168.1.10 er greit), og ikke vis til serverversjonen i koden. Noen gamle
commits har en lokal adresse og et maskinnavn; historikken skrives ikke om. Repo-innstillinger (beskrivelse, emner)
kan ikke endres fra Claude-økta (proxyen stopper det); eieren gjør det under «About» på GitHub.
`README.md` er forsiden på GitHub: skrevet for andre brukere, uten utviklernotater (de står her).

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Flutter kan ikke kjøres i Claude-økta** (pub.dev og Googles nedlastinger er stengt). Skriv koden nøye,
  og la GitHub Actions analysere, teste og bygge: `gh run list --repo ungerdas/fyrlys`,
  `gh run view <id> --repo ungerdas/fyrlys --log-failed`, `gh run watch <id> --repo ungerdas/fyrlys`.
  Advarsler fra `flutter analyze` stopper bygget (info gjør ikke det), f.eks. ubrukte importer.
  Loggene og artefaktene kan **ikke** lastes ned herfra (de ligger i blob-lagring som er stengt). Når et steg
  feiler, legger workflowen slutten av loggen som merknad; les den med
  `gh api repos/ungerdas/fyrlys/check-runs/<jobb-id>/annotations` (jobb-id fra `gh run view <id> --json jobs`).
- Windows-mappen lages av `flutter create --org no.fyrlys --project-name fyrlys --platforms=windows` i hvert bygg. I
  repoet ligger bare `windows/runner/resources/app_icon.ico` og `windows/installer/fyrlys.iss` (2.1.13, Inno Setup:
  `Fyrlys-oppsett.exe`, per bruker uten administrator i `{autopf}` = `%LOCALAPPDATA%\Programs\Fyrlys`, snarveier,
  norsk; AppId `{6E2B8C41-…}` må aldri endres, oppdater.ps1 setter `DisplayVersion` under den; ISCC fra choco hvis
  den mangler på løperen), og det skrives ikke over. Vindustittelen og filinfo
  settes med `sed` i workflowen (`main.cpp`/`Runner.rc`): alt er «Fyrlys» (2.1.19; før sto organisasjonen fra `--org`
  i LegalCopyright). CompanyName og ProductName bestemmer mappen innstillingene ligger i (`%APPDATA%\Fyrlys\Fyrlys`),
  så de må aldri endres; workflowen stopper om de ikke stemmer. Ikonet er tegnet fra `fyrlys.svg` i nettversjonen.
- Videoavspilling kan ikke testes her: si tydelig hva som bare er testet med tester, og hva eieren må
  prøve på Windows-PC-en sin.
- Flutter- og media_kit-kildene kan hentes for å sjekke API-er (github.com er åpent for git):
  `git clone --depth 1 --branch stable --filter=blob:none --sparse https://github.com/flutter/flutter.git`
  og `git sparse-checkout set packages/flutter/lib packages/flutter_test/lib` (tilsvarende for media-kit/media-kit).
  `unnecessary_import` er en advarsel og stopper bygget; sjekk hva `material.dart` eksporterer.
- **Versjoner** (eieren 26.10): hver oppdatering han får (hver push til main som bygges), får neste
  patch-versjon i pubspec: 2.1.2, 2.1.3, 2.1.4 … Øk før hver push som bygges. Feiler bygget i CI (eller avbrytes
  før releasen), har han ikke fått noe, og rettelsen beholder nummeret. Det er versjonen vi snakker om, aldri
  byggnummer eller commit (eieren 26.10: «bygg 30 sånt kan du droppe»). Skriv avsnittet `## vX.Y.Z` i
  `CHANGELOG.md` før push: det blir teksten i releasen.
- **Releaser** (eieren 26.10: «vi er ferdige med testbygg»): jobben `release` legger hver versjon ut som en vanlig
  GitHub-release `vX.Y.Z` («Fyrlys X.Y.Z», blir «Latest»), med `Fyrlys-oppsett.exe` og `Fyrlys-windows.zip` (faste
  navn, så `releases/latest/download/<fil>` alltid er siste versjon; appen oppdaterer seg fra zip-fila; v2.1.10–
  v2.1.11 har også APK-er; artefaktene hentes med navn, actions checkout@v7, upload-artifact@v7, download-artifact@v8), teksten fra CHANGELOG.md og
  byggnummeret skjult som `<!-- bygg N -->` (appen leser det). Finnes releasen alt (samme versjon på nytt), byttes
  filene (andre filnavn slettes først) og teksten. Appen spør `releases/latest`. (Fram til 2.1.9 lå versjonene i
  releasen `testbygg` med byggnummeret i navnet; den er slettet, og reservene for den er fjernet i 2.1.13.)
  Gamle releaser: v0.1.0 (forhåndsutgivelse) og v2.0.0 (andre filnavn, ingen byggnummer) ligger der fortsatt.
  Offentlig repo: Actions-minuttene er gratis; et bygg tar rundt 10 minutter. Bruk `[skip ci]` når en endring
  bare gjelder notater eller README. Versjonen står nederst i menyen (`appBuildLabel`; `--dart-define`
  FYRLYS_VERSION/BUILD/COMMIT/REPO, `lib/build_info.dart`); byggnummeret (`--build-number`) er `github.run_number`. Kjøringer kan avbrytes med `gh run cancel <id> --repo ungerdas/fyrlys`.

## Arkitektur (`lib/`)
- `core/source.dart` – `TvSource` (`kind` `xtream`/`m3u`, `hasVod`): kilde til kanaler, EPG, strømadresser og
  favoritter. `PlayTarget(urls, localShift:)`. Begge kildene spiller rett fra leverandøren (`localShift: true`).
  TV-arkivet (2.1.14): `archive(channel)` (programmene, `EpgEntry.inArchive`) og `archiveClip(channel, program)` →
  `ArchiveClip(start, stop, urlsAt(from))`, som gir adressene fra et punkt i programmet og hvor strømmen faktisk
  begynner (et helt minutt). `Channel.archiveDays`/`hasArchive` (JSON `arc`). Bare Xtream; M3U har det ikke.
  - `core/xtream_source.dart` – Xtream Codes (port av `xtream.py`): `player_api.php`,
    User-Agent som VLC, strøm `/live/<bruker>/<passord>/<id>.m3u8` og `.ts` som reserve, EPG i base64.
    Arkivet: `tv_archive`/`tv_archive_duration` i get_live_streams, programmene fra `get_simple_data_table`
    (`parseArchive`: begynt de siste N dagene, `has_archive` 0 = ikke lagret, det som går nå kan alltid ses fra start),
    strømmen `/timeshift/<bruker>/<passord>/<minutter>/<ÅÅÅÅ-MM-DD:TT-MM>/<id>.m3u8` (så `.ts`), på minuttet, ut
    programmet. Starten i serverens tid: `serverClockOffset` (time_now mot timestamp_now i server_info, hentes én gang
    med player_api.php uten action), `archiveOffset` (går serveren likt med PC-en nå, brukes PC-ens sone med
    sommertid; ellers serverens forskjell som den er; uten svar PC-ens, som Kodi), `xtreamTime`. Ikke prøvd mot en
    ekte leverandør: tidssonen og om HLS-varianten finnes, er usikkert.
  - `core/m3u_source.dart` (2.1.6) – en vanlig M3U-liste: `parseM3u` (`#EXTINF` med tvg-id/tvg-name/tvg-logo/
    group-title/tvg-chno, `#EXTGRP`, `url-tvg`/`x-tvg-url` i toppen; filmer/episoder etter sti eller filtype hoppes
    over), kanal-id = `stableHash` av tvg-id+navn (ellers gruppe+navn), kategorier = gruppene, nummer = tvg-chno
    eller plassen i lista. Store lister (> 200 kB) og XMLTV leses i en isolate. TV-guide fra XMLTV (`parseXmltv`
    med regex, gzip, bare −2 t til +24 t, hentes hver 6. time; egen EPG-lenke går foran lista sin), kobles på
    tvg-id, ellers display-name. Ingen filmer/serier (`hasVod: false`, fanene skjules). `Session.loginM3u`: en
    Xtream-lenke (get.php/player_api.php med username og password) prøves først som Xtream Codes.
  - Filmer og serier (bare Xtream; `core/vod.dart`: modellene, `pageOf`/`catalogOf` for filtrering, sortering og
    sider à 120, `episodeCode`, `ratingText`): hele lista hentes (`get_vod_streams`/`get_series`, 30 min) og
    filtreres i appen; filene er `/movie/` og `/series/<bruker>/<passord>/<id>.<ext>`.
- `core/cache.dart` – det som tas vare på mellom gangene (2.1.3): `ListCache` (`FileListCache` i
  `getApplicationSupportDirectory()/lister`, én JSON per kilde med nøkkelen `kind|label`; `MemoryListCache` i testene)
  og `ImageStore` (bildene i `getApplicationCacheDirectory()/bilder`, filnavn `stableHash(url)`, fornyes etter 14 dager,
  det gamle brukes når nettet feiler, 404 huskes i 10 min, `prune()` ved start holder det under 300 MB). Settes opp i
  `main.dart` (path_provider); uten dem (testene) hentes alt som før.
- `core/session.dart` – tilstanden (ChangeNotifier): innloggingene (2.1.14, `SavedLogin`): lista i `logins` (id, navn,
  slag), den i bruk i `login`, og hver innlogging (`toPrefs()` som JSON) kryptert med DPAPI i `login_protected:<id>`
  via `core/secrets.dart` (`SecretCodec`; `DpapiCodec` = CryptProtectData/CryptUnprotectData med FFI; `NoSecretCodec`
  utenfor Windows, og i testene en egen), eller i klartekst i `login_source:<id>` når krypteringen ikke kan leses
  tilbake (krypteres når det går). Id = `Session.loginId` (`stableHash` av leverandør + bruker, ikke passordet), så
  samme konto igjen blir samme innlogging og får favorittene tilbake. Favoritter, favorittkategorier, sist sett,
  `resume`, `continue` og `guide_cat` ligger per innlogging (`<navn>@<id>`, `_k`); lyd, språk, bilde, tema og vindu
  er felles. `_migrate` flytter innloggingen fra før (`source_protected`/`source`) og disse nøklene uten id over én
  gang. `switchLogin`, `renameLogin`, `removeLogin` (data blir liggende; var den i bruk, tas den neste som kan åpnes),
  `logout` = fjern den i bruk, `useSource` for testene. Kan den gamle innloggingen ikke åpnes, blir dataene uten id
  liggende og går til den første innloggingen (`_moveLegacy` i `_use` når lista er tom). Kanallista på disk har
  nøkkelen `loginId` (2.1.15; før `kind|label`, som to M3U-lister fra samme vert delte). `app.dart` gir HomePage
  nøkkelen `innlogging:<id>`, så den begynner på nytt ved bytte. Lister, EPG-mellomlager (5 min, 4 om gangen),
  `epg(id, limit:)` (en lengre liste fra guiden brukes også av kortene; `cleanEpg` i `models.dart` slår sammen
  doble programmer og kutter overlapp, som `clean_epg` på serveren), favoritter (lokalt, `favorites` og
  `favoriteCategories`), «sist sett», lys/mørk, og «fortsett der du
  slapp» (`resume` i shared_preferences: «film:<id>»/«episode:<id>» → [sekunder, lengde, når], maks 300;
  `resumeAt` gir null under 30 s og over 95 %, `watched` gir streken). Språkene (`languages`/`saveLanguages`,
  `lang_audio`/`lang_subs` i shared_preferences; `LanguagePrefs` og kodene i `core/languages.dart`). Lista fra
  `listCache` vises med en gang (`_startLists`), `load` skriver den nye; `_prefetchEpg` henter programinfo for 12
  favoritter og 8 sist sett når lista er klar.
- `ui/login_page.dart` (to valg: «M3U-lenke» med valgfri EPG-lenke, og «Xtream Codes»; `adding: true` = en til, med
  AppBar «Ny innlogging», lukkes når den er lagt til), `ui/settings_page.dart` (2.1.16, eierens forslag: tannhjulet
  øverst erstatter menyen med tre prikker; seksjonene Innlogging (bytt, «Gi nytt navn», «Logg ut og fjern», «Legg
  til innlogging», «Logg ut av …» med `confirmLogout`; abonnementet fra `account()` via `accountLine`), Utseende
  (`Session.setThemeMode`: som Windows/mørkt/lyst, `theme` = system/dark/light), Avspilling (språkdialogen,
  deinterlacing, jevn bevegelse; gjelder neste avspilling), Kanaler og TV-guide («Hent listene på nytt»),
  Oppdateringer (status fra `Updater`, «Start på nytt nå»), versjonen nederst; lukkes av seg selv når den siste
  innloggingen er borte. Lys/mørk-knappen i toppen står fortsatt. `logins_dialog.dart` fra 2.1.14 er borte),
  `ui/home_page.dart`
  (TV/TV-guide/Filmer/Serier, de to siste bare med `hasVod` (`_sectionList`/`_current`): SegmentedButton i toppen
  ≥ 900 px (ikoner ≥ 1200), ellers NavigationBar nederst; tannhjulet åpner innstillingene (2.1.16; «Se etter
  oppdateringer» står der, oppdateringsserveren er fjernet i 2.1.11); TV har sidemeny ≥ 900 px med ikoner, ellers nedtrekksliste; søket gjelder fanen du er på,
  på Hjem alle kanalene), `ui/channel_card.dart` (`showNext`: også det som kommer etterpå).
- `ui/start_view.dart` – Hjem (filteret `home`, valgt når appen starter, 26.10 for 2.0.3; eieren ville ha vekt på TV,
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
  er huket av; «Foretrukne språk …» nederst gjelder straks).
- `ui/guide_view.dart` – TV-guiden, som på nettsiden: 6 timer fra halvtimen før denne halvtimen (`guideStart`),
  5 px/min (4 på smale skjermer), «nå»-strek, «Til nå», kategori (★ Favorittkanaler / Alle / dine kategorier
  først; huskes i `guide_cat`) og søket i toppen. Kanalnavnene er en egen liste til venstre som rulles sammen med
  programmene (to ScrollControllere som følger hverandre); programmene ligger i en vannrett rulling, og titler
  som begynte før det synlige, flyttes inn (ListenableBuilder på den vannrette). Hver rad henter
  `session.epg(id, limit: 14)` etter 150 ms framme (`epgCached` gir det som alt er hentet uten å vente). Trykk på
  det som går nå eller på kanalnavnet = spill; senere/tidligere program = info med «Se kanalen». På PC kan
  guiden dras med musa, og programmene har verktøytips. Kanaler med arkiv har en klokke-knapp («TV-arkiv») ved navnet.
- `ui/multiview_page.dart` (2.1.17, eieren: «Hvis man har flere abo så burde man få se multiview») – ett bilde per
  tilkobling i alle innloggingene (den i bruk først; `account().maxConnections`, 0/ukjent = 1), høyst `multiviewMax` 4:
  to side om side (over hverandre i et høyt vindu), tre–fire i 2×2. Hvert `_Slot` har sin kilde (`Session.sourceFor`:
  den i bruk deles, de andre åpnes og lukkes av siden), avspiller (`setup()` uten det store bufferet), kanal, EPG
  (hvert minutt) og nye forsøk (HLS → TS, tre per minutt). Lyd bare i det valgte (`_applyVolumes`, volumet fra
  Session), klikk = velg, dobbeltklikk/Enter = stort bilde (`_big`), C = kanalvalg (`_ChannelPicker`: favorittene til
  den innloggingen via `Session.favoritesOf`, ellers alle, med søk), 1–4/piler, M, F, Esc. `Session.canMultiview` (to
  innlogginger, eller `_connections` ≥ 2 fra `account()` etter `_attach`) styrer knappen «Multiview» i toppen av
  TV-siden (med kanalen du så sist) og i spilleren (V; `_away` stopper direktesendingen og tar kanalen med,
  `startFull`). Testet i `multiview_test.dart`; fire mpv-er samtidig i ekte bruk er ikke prøvd.
- `ui/archive_page.dart` (2.1.14) – TV-arkivet for én kanal: programmene nyeste øverst, dag for dag (`archiveDay`:
  I dag / I går / «Lørdag 24. oktober»), «Går nå», «Ikke i arkivet» dempet, strek for det du har sett. Et trykk lager
  `VodPlayItem`-er for alle som kan ses (`archiveItems`/`archivePlayItem`, nøkkel `arkiv:<kanal>:<start>`) og åpner
  filmspilleren på det valgte.
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
  `Media(start:)`, går til neste episode 1,5 s etter slutten). Arkivet (2.1.14, `VodPlayItem.archive`): `setup(live:
  true)` (bufferet), lengden er programmets, posisjonen `_base` + strømmens; HLS-adressen først og MPEG-TS ved feil
  før start (den som virket, huskes i `_variant`); spoling i HLS med kjent lengde = `seek`, ellers i bufferet
  (`liveCache` + `seekBy`), ellers åpnes strømmen på nytt fra minuttet og resten hoppes over når det er hentet
  (`_skip`); ←/→ samles i 450 ms; slutter strømmen før programmet (det som går nå), åpnes den igjen inntil tre ganger i
  minuttet. `startFull`: åpnet fra TV-spilleren i fullskjerm.
- `ui/player_page.dart` – som spilleren på nettsiden (alltid mørk): bildet med kontroller og programinfo under,
  kanallista (`ui/side_list.dart`: lista du kom fra / ★ Favoritter, søk) til høyre fra 860 px, ellers under.
  Fullskjerm = bare bildet (window_manager; et maksimert vindu gjøres vanlig først,
  ellers lar window_manager 0.5.x tittellinja stå og bunnen havner bak oppgavelinja; vindusanimasjonene er av
  mens det skjer, via `DwmSetWindowAttribute` i `ui/window_effects.dart` (FFI)), kanallista over bildet med C.
  Bildet ligger under en GlobalKey, så det flyttes mellom oppsettene uten å starte på nytt.
  Volum (glidebryter, musehjulet over bildet, lagres i Session), ⇄/Backspace, tastatur (OK/Enter =
  fullskjerm/kanalliste). Infoen viser oppløsning, kodek/hwdec/lyd (mpv-egenskaper)
  og hvor strømmen kommer fra. Nye forsøk ved brudd/fast bilde, tre per minutt. Kanalbytte (2.1.3): ↑/↓ setter
  `_pendingZap` (kanalinfoen viser den, programinfo via `session.epg`) og starter den etter 650 ms (`_commitZap`; OK
  straks, Esc avbryter); `_banner` nederst i bildet (`ValueKey('channel-banner')`) vises mens du blar, 4 s etter
  `_switchTo` og til den nye kanalen har startet (`_switching`), ikke ved første åpning, spoling eller nye forsøk;
  toppstripa i fullskjerm skjules imens. Den lille spinneren i banneret går til bildet starter: ingen
  `pumpAndSettle` i tester etter et kanalbytte (den falske avspilleren starter aldri).
  Pause og tilbakespoling i appen selv (2.1.4, `PlayTarget.localShift`; tilbakespoling på serveren er borte i 2.1.6):
  `setup(live: true)` gir mpv `cache=yes`, `demuxer-seekable-cache=yes` og `cache-on-disk` i
  `<cache>/mpv` (`MpvPlayback.cacheDir`, ryddes ved start; 2000/1000 MiB bak/foran, 400/200 i minnet uten
  mappe). Vakta spør `liveCache()` (fra `demuxer-cache-state`: `reader-pts`, `cache-end`,
  `seekable-ranges`) hvert 2. s; «direkte» er det minste avspilleren har foran mens du ser direkte (`_liveAhead`,
  strømmen kommer i biter, derfor 15 s slakk i `_atLive`), bak direkte = foran − det. Spoling = `seekBy` (mpv
  `seek <s> relative`) i bufferet, uten å åpne på nytt (`package:clock` for tida på pause, så testene kan spole den).
  Ikke prøvd i ekte mpv. Tidslinje, −10/+10 (samles i 450 ms), «DIREKTE» (trykk = direkte), ←, → (på PC og i
  fullskjerm; ellers inn i lista), L/End. Kanaler med arkiv (2.1.14): «Se fra start» (programmet som går nå, når det
  har gått et minutt) og «TV-arkiv» (A) i kontrollene (ikke i smalt vindu) og som knapper under bildet. `_away` stopper
  direktesendingen mens arkivet er oppe (én tilkobling; også et kanalnummer under tasting avbrytes) og åpner kanalen
  igjen etterpå; `_shownFull = null` etter filmspilleren, så vinduet settes slik spilleren er. Filmspilleren med
  `startFull` tar ikke vinduet ut av fullskjerm når den lukkes, og `WindowFullscreen.set` gjør ingenting når vinduet
  alt er slik (`_on`), så `_wasMaximized` ikke overskrives (2.1.15, funnet i gjennomlesing).
- `ui/playback.dart` – `Playback`: mpv via media_kit (`MpvPlayback`), en falsk i testene (`playbackFactory`
  byttes ut i testene for sider som lager avspilleren selv). Fullskjerm for begge spillerne:
  `WindowFullscreen` i `ui/window_effects.dart`. Språk: `setLanguages` setter `alang`/`slang` og
  `subs-with-matching-audio=no` når undertekstspråk er valgt; ved ny adresse settes `aid=auto` og `sid=auto`/`no`
  (et spor valgt for hånd står ellers i mpv til neste fil; samme adresse, f.eks. etter spoling, beholder det).
  `tracks()` leser `aid`/`sid` fra mpv (media_kit vet bare om spor valgt via `setAudioTrack`). Bildeundertekster
  (PGS/DVB) vises ikke: media_kit tegner tekstundertekster selv (`sub-visibility=no` uten libass).
- `core/updater.dart` – oppdatering fra siste release (bare bygg med byggnummer), rett fra
  `api.github.com/repos/<repo>/releases/latest` (`_latest`/`_release`; byggnummeret fra `<!-- bygg N -->`; 404 =
  privat repo, feil med forklaring). Blir repoet privat igjen, virker ikke oppdateringen
  (2.1.6–2.1.10 kunne gå via Fyrlys-serveren, `/api/app/release`; fjernet i 2.1.11, finnes i historikken). Sjekker etter `session.restore()` (+8 s) og hver 6. time, byggnummeret fra navnet,
  `-windows.zip` lastes ned til `%LOCALAPPDATA%\Fyrlys\oppdatering\bygg-N` (størrelsen sjekkes),
  så `klar.json`. Legges inn når appen lukkes (`didRequestAppExit` i `app.dart`), med «Start på nytt nå», eller
  før appen vises neste gang (`beforeStart` i `main.dart`). Et PowerShell-skript (bare ASCII) venter på prosessen,
  pakker ut og kopierer med robocopy, skriver `resultat.txt` (vises i banneret) og `oppdatering.log`.
  `klar.json` slettes før skriptet startes, og `i-gang.txt` (90 s) hindrer at appen starter midt i, så det
  aldri blir en løkke. Krever at Fyrlys-mappen er skrivbar (ikke Programfiler). Banner og «Se etter
  oppdateringer» i `home_page.dart`.
- `core/single_instance.dart` (2.1.13) – bare én Fyrlys: `SingleInstance.isSecond` lytter på 127.0.0.1:47853; en ny
  start sender `fyrlys:vis`, får `fyrlys:ok` og avslutter (`main.dart`, rett etter `beforeStart`, før mpv-bufferet
  ryddes), og den første henter vinduet fram (`_bringToFront`). Svarer noe annet på porten, starter appen som vanlig.
- `ui/window_memory.dart` (2.1.13) – `WindowMemory.restore` før `runApp`: størrelse/plass (`window` i
  shared_preferences, bare når tittellinja ligger på en skjerm, `screen_retriever`) og maksimert; lagres 600 ms etter
  flytting/endring, ikke i fullskjerm eller minimert (maksimert beholder den vanlige størrelsen).
- `core/failure.dart` (2.1.20) – `explainFailure(src, url, fallback:, channel:)` når en strøm ikke kan spilles etter
  forsøkene: `busyText` fra `account(fresh: true)` først, ellers `TvSource.streamStatus(url)` (GET, bare svaret leses;
  `httpStatus` med kildens klient) og `refusedText(kode)` for 400 og over, ellers det mpv sa. Brukes av alle tre
  spillerne (filmspilleren viser mpv-teksten straks og bytter den ut).
- Bildeformat og lydforsinkelse (2.1.20, `core/picture.dart`: `PictureFormat` original/zoom/stretch/wide/classic,
  `ChannelView`, `clampAudioDelay` ±2 s i steg på 50 ms): `Playback.view(format:)` (media_kit `Video(fit:, aspectRatio:)`)
  og `Playback.setAudioDelay` (mpv `audio-delay`). TV-spilleren husker dem per kanal (`Session.channelView`/
  `saveChannelView`, `channel_view@<innlogging>`, 300 kanaler), filmspilleren så lenge den er åpen. Valgene ligger i
  `TracksButton` (`ui/picture_dialogs.dart`: `showFormatDialog`, `showAudioDelayDialog` som gjelder mens du drar), Z blar.
- Minispiller (2.1.20): `MiniWindow` i `ui/window_effects.dart` (480×270 nederst til høyre på skjermen vinduet står på,
  `TitleBarStyle.hidden`, `setAlwaysOnTop`; størrelse/maksimert tilbake etterpå; tar vinduet ut av fullskjerm først)
  og `MiniControls` i `ui/mini_player.dart`. I TV- og filmspilleren (`_mini`, I, knappen ved fullskjerm; Esc,
  dobbeltklikk og F gir stort vindu; dra i bildet = `dragWindow`). `_away` går ut av minispilleren før arkivet og
  multiview. `WindowMemory` lagrer ikke mens den er aktiv. Ekte vindu er ikke prøvd.
- Feilrapport (2.1.20): `core/app_log.dart` (`AppLog` med de 400 siste linjene fra `debugPrint`, `FlutterError` og
  uventede feil, satt opp i `main.dart`; `scrub` fjerner vertsnavn, IP, `/live|movie|series|timeshift/<bruker>/<passord>`,
  `username=`/`password=`, e-post og `C:\Users\<navn>`), `core/report.dart` (`buildReport`: versjon, Windows, antall og
  slag innlogginger (ikke navnene), abonnementet, listene, innstillingene, loggen og slutten av oppdateringsloggen;
  `saveReport` i Nedlastinger, `showInExplorer`, `openUrl` byttes ut i testene). Innstillinger → Hjelp. Skjemaene for
  GitHub-saker ligger i `.github/ISSUE_TEMPLATE` (feil, ønske).
- Språk (grunnlaget i 2.1.20, engelsk i 2.1.21): `l10n/tr.dart` (`tr('norsk tekst', {'navn': verdi})` slår opp i
  `english` når `appLanguage` er 'en'; norsken er nøkkelen). `english` i `l10n/en.dart` slår sammen `en_core`,
  `en_home`, `en_player`, `en_settings` og `en_vod` (etter hvor teksten står; samme nøkkel i flere filer må ha samme
  engelsk). `l10n/dates.dart`: `weekdayName`, `monthName`, `longDate`, `shortDate`. `Session.language` ('auto'/'no'/
  'en' i `language`, valget i Innstillinger → Utseende) og `systemLanguage` fra Windows (`languageOfLocale`; `main.dart`
  setter `appLanguage` før oppdateringen leses). Ved bytte bygger `app.dart` alt på nytt (`_rebuildAll`, uten at sider
  lukkes). Regler: all tekst brukeren ser i `tr()` (ikke debugPrint, nøkler, id-er), aldri `$` i nøkkelen, ikke tr() i
  `const` eller toppnivå-/static-verdier, hele setninger som nøkler (egne for entall/flertall).
  `test/l10n_test.dart` finner alle `tr('…')` i lib/ og krever engelsk med de samme `{navnene}`. Testene ellers venter
  norsk (`appLanguage` er 'no' i testene). Installasjonsprogrammet har engelsk (`Default.isl`, først = reserven) og
  norsk, valgt etter Windows. `README.en.md` er den engelske forsiden.
- `theme.dart` – fargene fra nettversjonen («Fyrlys om natta» / «Nordisk lys»).
- Tester i `test/`: navn, Xtream-kilden (også arkivet: klokka, tidene, `parseArchive`, adressene), M3U-kilden og
  innloggingen (`m3u_source_test.dart`, med MockClient og `http.runWithClient`; også krypteringen av innloggingen),
  flere innlogginger (`logins_test.dart`: flyttingen fra før, bytte, navn, logg ut, innstillingene), innstillingene
  (`widget_test.dart`: tema, bildet, listene, oppdateringer, `accountLine`), TV-arkivet
  (`archive_test.dart`: guiden, arkivsiden, filmspilleren med reserve/spoling/neste, «Se fra start» i spilleren;
  `FakeSource(withArchive: true, name:)`, `FakePlayback.fail`), oppdateringen (`updater_test.dart`), vinduet og én Fyrlys
  (`window_test.dart`, ekte lokal port),
  widget-tester for TV-siden og spilleren (`player_test.dart`, tilbakespoling i `timeshift_test.dart`) med falsk
  kilde og avspiller (`fakes.dart`),
  filmer og serier (`vod_source_test.dart`: kildene og lister; `vod_test.dart`: fanene, detaljsiden, spilleren,
  fortsett og neste episode), TV-guiden (`guide_test.dart`).

## Status
- 25.10.2026: v0.1 skrevet. Eieren prøvde Windows-versjonen og savnet volumkontroll og spilleren slik den er
  på nettsiden før fullskjerm. Laget samme dag (spilleren som på nettsiden, volum, byggnummer i menyen), testet med
  widget-tester. Ikke prøvd på ekte enheter ennå; Android TV-navigasjon er helt uprøvd.
- 25.10.2026: automatisk oppdatering fra releasen `testbygg`. Eieren ville beholde repoet privat, så den går via
  Fyrlys-serveren (`app/appupdate.py` i server-repoet, nøkkelen i `data/github.json` på serveren). Serverdelen er
  prøvd mot ekte GitHub, appdelen bare med tester. Første bygg med den må lastes ned for hånd.
  Nøkkelen ligger på serveren (virker, 25.10), og bygg 6 kjører på PC-en hans. Bygg 6 → 7 feilet: skriptet
  startet aldri (tom logg). `ProcessStartMode.detached` gir `DETACHED_PROCESS` (ingen konsoll) på Windows, og
  da kommer ikke Windows PowerShell i gang. Bygg 8 starter det i vanlig modus (Dart bruker da `CREATE_NO_WINDOW`:
  skjult konsoll), skriptet skriver `i-gang.txt` selv, og appen logger oppstarten i `oppdatering.log`.
  Bygg 7 → 8 måtte derfor også legges inn for hånd. Bygg 9 → 10 kom av seg selv (bekreftet av eieren 25.10):
  oppdateringen virker fra start til slutt. Fullskjerm fra maksimert vindu virker (bygg 9), animasjonen er
  fjernet i bygg 10 (ikke bekreftet ennå).
- 25.10.2026: Filmer og Serier i appen (ett bygg). Testet med kilde- og widget-tester, ikke med ekte avspilling:
  spoling, fortsett og neste episode i mpv, store lister fra leverandøren og fjernkontroll på Android TV er uprøvd.
- 25.10.2026: TV-guide i appen (eieren savnet den). Testet med widget-tester; ikke prøvd med ekte EPG eller
  fjernkontroll ennå.
- 25.10.2026: pause/tilbakespoling i direktesending og «Fortsett å se» (eierens valg). Bare testet med tester;
  om `live_start_index` virker i mpv-en til media_kit, er ikke prøvd.
- 26.10.2026: Apple TV vurdert og lagt bort (eieren stoppet det). Flutter har ingen offisiell tvOS (bare
  flutter-tvos, uoffisiell) og media_kit finnes ikke for tvOS, så det ville blitt en egen Swift-app (AVPlayer for
  serverens HLS, MPVKit for MKV), bygget på GitHubs macOS-maskiner (~10x prisen per minutt) og lagt i TestFlight
  (krever betalt utviklerkonto). Enklere alternativ om det kommer opp igjen: M3U/XMLTV eller Xtream-API fra
  Fyrlys-serveren for en ferdig Apple TV-app.
- 26.10.2026: v2.0.0 (eierens valg av nummer) etter en gjennomgang av koden med to uavhengige lesere. Rettet:
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
- 26.10.2026: 2.1.3, «mer smooth» (eierens ønske, alle sju forslagene): lista og bildene på disk, programinfo
  ved start, kanalinfo ved bytte, rask blaing, overganger og fokus. Testet med tester; ikke prøvd på ekte enheter.
- 26.10.2026: 2.1.4: TV direkte (uendret strøm via serverens mellomstasjon, direkte-økter på serveren for «Ta over»
  og seere, se server-repoet) og pause/spoling i appens eget buffer (eierens valg: «Appen husker selv»). Testet med
  tester; mpv-bufferet, `demuxer-cache-state` og spolingen i ekte mpv er ikke prøvd.
- 26.10.2026: 2.1.5: bildeinnstillinger (eieren ville prøve dem): `PicturePrefs` (`core/picture.dart`,
  `deinterlace`/`smooth_motion` i shared_preferences, deinterlacing på som standard), `Playback.setPicture`
  (`deinterlace=auto`, `yes` på eldre mpv; jevn: `video-sync=display-resample`, `interpolation`, `tscale=oversample`,
  `display-fps-override` fra Flutters `display.refreshRate`), to valg nederst i `TracksButton`, og `describe` med
  fps/deinterlacet, bitrate, tapte bilder og om `display-sync-active`, hvert 5. s. Ikke prøvd i ekte mpv; usikkert
  om display-sync virker med media_kits libmpv-rendering.
- 26.10.2026: 2.1.6: innlogging med M3U-lenke eller Xtream Codes, Fyrlys-serveren bare til oppdateringer (eierens
  valg). Fjernet `fyrlys_source.dart`, tilbakespoling på serveren (`LiveWindow`, `live_start_index`), «direkte»-økter
  og hjerteslag fra appen (serverens API-er for dem står igjen i server-repoet). Testet med tester; ekte M3U-lister og
  XMLTV fra leverandøren hans er ikke prøvd.
- 26.10.2026: 2.1.7: 404 fra GitHub/oppdateringsserveren er en feil med forklaring, ikke «du har siste versjon»
  (eieren sto på 2.1.4 med den meldingen mens 2.1.6 var ute; serveren svarer nå 502 i det tilfellet).
- 26.10.2026: repoet gjort offentlig (eieren), README skrevet om som forside. 2.1.8: oppdateringene rett fra
  GitHub (oppdateringsserveren valgfri, ikke lenger satt av seg selv fra en gammel innlogging). Notatene flyttet til
  `.claude/CLAUDE.md`.
- 26.10.2026: 2.1.9: versjonen uten byggnummer og commit (menyen, releasen), CHANGELOG-avsnittet som tekst i
  releasen, byggnummeret i `<!-- bygg N -->` (bro, se Versjoner).
- 26.10.2026: 2.1.10: første vanlige release (`v2.1.10`), `testbygg` slettet.
- 26.10.2026: 2.1.11: «Oppdateringsserver» fjernet fra menyen (eieren: trengs ikke), oppdateringene bare fra
  GitHub.
- 26.10.2026: 2.1.12: bare Windows (eieren). Android-bygget, `android/`, `lib/platform.dart` (`isDesktop`) og
  telefon-/TV-greinene i spillerne (immersive, `_suspended`/livssyklus, telefon på tvers) er fjernet. Et Linux-bygg
  med selvoppdatering ble laget samme kveld, men aldri lagt ut (kjøringen ble stoppet; koden er i commit ecaf411).
- 26.10.2026: 2.1.13 (eierens valg 1–6): installasjonsprogram, innloggingen kryptert (DPAPI), vinduet husker seg,
  bare én Fyrlys, død kode fjernet («Ta over»/`BusyException`, delte favoritter og meldingsstrømmen, `prepare`/`close`
  i `TvSource`, testbygg-reserver, flyttingen fra Fyrlys-serveren), nye versjoner av actions. Testet med tester;
  Installasjonsprogrammet virker på PC-en hans (eieren 26.10: «Funka veldig fint»); DPAPI, vinduet og
  én-om-gangen er ikke bekreftet hver for seg.
- 26.10.2026: 2.1.14 (eierens valg 1 og 12 fra lista over det som mangler): TV-arkiv med «Se fra start» (Xtream),
  og flere innlogginger med egne favoritter. Testet med tester; arkivet mot leverandøren hans (tidssonen i adressen,
  HLS eller TS, spoling i ekte mpv, om timeshift godtar en varighet forbi nå for det som går) er ikke prøvd.
  2.1.15: fire rettelser fra en uavhengig gjennomlesing (fullskjerm etter «Se fra start», kanalliste-nøkkelen,
  kanalnummer under arkivet, favoritter når den gamle innloggingen ikke kunne flyttes).
- 26.10.2026: 2.1.16: innstillingssiden (eieren: «kanskje de tre prikkene skal byttes ut med et tannhjul og så åpner
  det et innstillingsvindu?»). Testet med widget-tester. Den virker hos ham (skjermbilde 26.10: abonnementet viser
  «aktiv til … · 1 tilkobling»).
- 26.10.2026: 2.1.17: multiview over flere abonnementer. Testet med widget-tester.
- 26.10.2026: 2.1.18: eieren fikk «Kanalen kunne ikke spilles (Failed to open …/live/***/***/<id>.ts)» i
  TV-spilleren. Sannsynlig årsak (feil fra 2.1.14): `_away` åpnet kanalen igjen så snart `nav.push` var ferdig, mens
  filmspilleren/multiview strømmet til `dispose` etter tilbakeovergangen (to strømmer på én tilkobling). Nå stopper
  alle spillerne strømmen i `PopScope.onPopInvokedWithResult(didPop: true)` (kalles i `Navigator.pop`, før
  `push`-framtiden er ferdig), og åpning som feiler prøves to ganger til etter 3 s (`_openTries`/`openTries`) før
  feilen vises; da spør spilleren `account(fresh: true)` og viser `busyText` når `active_cons` ≥ `max_connections`.
  Den egentlige årsaken var noe annet: diag og `/api/xtream/status?fresh=1` på serverversjonen viste HTTP 407 fra
  leverandøren for den ene kanalen (både HLS og TS) med `active` 0 av `max` 1, altså en kanal leverandøren avviser.
  Tilbudt: vise HTTP-koden fra leverandøren i feilmeldingen (ikke laget).
- 26.10.2026: 2.1.19: ingenting personlig i appen eller repoet (eierens ønske): `--org no.fyrlys`, all filinfo i exe-en
  «Fyrlys», kommentarene viser ikke til nettversjonen, notatene uten navn og serverrepo. Git-historikken har fortsatt
  en lokal adresse og et maskinnavn i gamle commits (ingen passord eller leverandør); å fjerne dem krever at
  historikken skrives om.
- 26.10.2026: 2.1.20 (eierens valg 4, 5, 11 og 13 fra lista over forbedringer; 3, engelsk, kommer i 2.1.21):
  tydeligere feilmeldinger med HTTP-koden, bildeformat og lydforsinkelse, minispiller, feilrapport og skjemaer for
  GitHub-saker. Testet med tester; mpv-egenskapene, minivinduet og Utforsker/nettleser fra appen er ikke prøvd på Windows.
- 26.10.2026: 2.1.21: engelsk (eierens valg 3), oversatt av fem agenter i hver sin del av lib/ og sett over etterpå.
  Testet med tester (bl.a. at alt er oversatt og at språket byttes i innstillingene).
- Ideer senere (lista fra 26.10, han valgte 1 og 12): søk i programmene, påminnelser, sortere favorittkanalene, skjule
  kategorier/kanaler, minispiller (alltid øverst), medietaster og Windows sin medieboks (SMTC), bildeformat og
  lydforsinkelse, sove-timer, bildeundertekster (DVB/PGS) med libass, sikkerhetskopi av favoritter og innstillinger,
  signering av exe-en.
