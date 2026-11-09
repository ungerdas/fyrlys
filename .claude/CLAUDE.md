# Fyrlys-appen – arbeidsnotater for Claude

Egen app for Fyrlys, en IPTV-spiller: Flutter med media_kit (mpv) som avspiller, for **Windows og Android-telefoner**
(eieren 26.10: «vi kjører kun Windows», så Android ble fjernet i 2.1.12; 1.11 ville han ha den tilbake: «Kan du lage
android mobil versjon? med Chromecast», i samme app og som APK fra GitHub, 2.1.26; Android TV og Linux er ikke med).
Den kommer **i tillegg til** Docker-versjonen
(nettside + server med ffmpeg) i et eget, privat repo.
Fra 2.1.6 (eieren 26.10: «Fyrlys server dropper vi») logger appen inn med M3U-lenke eller Xtream Codes og henter
alt rett fra leverandøren, og oppdateringene rett fra GitHub (fra 2.1.11 uten valg av oppdateringsserver); appen
bruker ikke Fyrlys-serveren til noe.
Ikke bland inn endringer der herfra. Repoet er **offentlig** (åpnet 26.10, så oppdateringene kommer rett fra
GitHub), og appen skal kunne deles med andre (eieren 26.10: «Fyrlys på windows er noe jeg vil dele, så der kan det ikke
være noe personlig»; appen og serverversjonen skal være helt adskilt). Hold appen, koden, testene, commit-meldingene,
filinfoen i exe-en og disse notatene fri for navn, hjemmenett, maskinnavn, leverandør, brukernavn, hemmeligheter og
e-postadresser (eksempeladresser som 192.168.1.10 er greit), og ikke vis til serverversjonen i koden. Unntak (eierens
valg 1.11, «Bygget inn for alle»): NRK sine egne direktesendinger i `core/public_streams.dart`. Noen gamle
commits har en lokal adresse og et maskinnavn; historikken skrives ikke om. Repo-innstillinger (beskrivelse, emner)
kan ikke endres fra Claude-økta (proxyen stopper det); eieren gjør det under «About» på GitHub.
`README.md` er forsiden på GitHub: skrevet for andre brukere, uten utviklernotater (de står her).

## Arbeidsmåte
- Svar alltid på **norsk**. Commit-meldinger på norsk med prefikset `Fyrlys:`. Push rett til `main`.
- **Flutter kan ikke kjøres i Claude-økta** (pub.dev og Googles nedlastinger er stengt). Skriv koden nøye,
  og la GitHub Actions analysere, teste og bygge: `gh run list --repo ungerdas/fyrlys`,
  `gh run view <id> --repo ungerdas/fyrlys --log-failed`, `gh run watch <id> --repo ungerdas/fyrlys`.
  Advarsler fra `flutter analyze` stopper bygget (info gjør ikke det), f.eks. ubrukte importer.
  Artefaktene kan **ikke** lastes ned herfra (blob-lagring som er stengt). Loggene kunne heller ikke før, men
  `gh run view <id> --repo ungerdas/fyrlys --log` virket 2.11 (f.eks. `| grep "Sjekk avspilleren"` for libmpv-sjekken).
  Når et steg feiler, legger workflowen også slutten av loggen som merknad; les den med
  `gh api repos/ungerdas/fyrlys/check-runs/<jobb-id>/annotations` (jobb-id fra `gh run view <id> --json jobs`).
- Android-mappen lages av `flutter create … --platforms=android` i Android-jobben (2.1.26). I repoet ligger bare
  `android/app/src/main/AndroidManifest.xml` (tillatelser, `CastService`, `ApkProvider`, http), Kotlin-filene i
  `android/app/src/main/kotlin/no/fyrlys/fyrlys/` (`MainActivity` med kanalen `fyrlys/android`, `CastService`,
  `ApkProvider`) og ikonene i `res/`; resten (Gradle, styles) lages av malen. applicationId `no.fyrlys.fyrlys`, minSdk
  24 (Flutter sin), arm64 + arm + x86_64 i én APK (2.1.29: `flutter build apk` uten `--target-platform`; libmpv fra
  media_kit_libs_android_video følger med for alle tre uansett, fordi Flutters `abiFilters` er alle tre, så med Flutter
  bare for arm64 valgte Android en ABI uten libflutter i BlueStacks (N32 = x86/armeabi-v7a, 64-bit = x86_64) og på
  32-bit-telefoner: hvitt vindu). APK-en signeres med apksigner etter bygget med hemmelighetene `ANDROID_KEYSTORE_B64`,
  `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (eieren lager nøkkelen og legger dem inn; de kan ikke settes eller
  leses herfra, proxyen stopper actions/secrets). Uten dem bygges APK-en, men legges ikke i releasen (en advarsel på
  kjøringen), fordi en APK med tilfeldig nøkkel ikke kan oppdateres. Mister han nøkkelen, må appen avinstalleres og
  installeres på nytt (innloggingen og favorittene forsvinner). Kotlin kan heller ikke kompileres her: feil kommer i
  Android-jobben (merknad fra build.log).
- Windows-mappen lages av `flutter create --org no.fyrlys --project-name fyrlys --platforms=windows` i hvert bygg. I
  repoet ligger bare `windows/runner/resources/app_icon.ico` og `windows/installer/fyrlys.iss` (2.1.13, Inno Setup:
  `Fyrlys-oppsett.exe`, per bruker uten administrator i `{autopf}` = `%LOCALAPPDATA%\Programs\Fyrlys`, snarveier,
  norsk; AppId `{6E2B8C41-…}` må aldri endres, oppdater.ps1 setter `DisplayVersion` under den; ISCC fra choco hvis
  den mangler på løperen), og det skrives ikke over. Vindustittelen og filinfo
  settes med `sed` i workflowen (`main.cpp`/`Runner.rc`): alt er «Fyrlys» (2.1.19; før sto organisasjonen fra `--org`
  i LegalCopyright). CompanyName og ProductName bestemmer mappen innstillingene ligger i (`%APPDATA%\Fyrlys\Fyrlys`),
  så de må aldri endres; workflowen stopper om de ikke stemmer. Ikonet er tegnet fra `fyrlys.svg` i nettversjonen.
  Visual C++-runtime (2.1.33; eieren 3.11 på en annen PC: «MSVCP140.dll ikke ble funnet»): steget «Visual C++-runtime i
  programmappen» kopierer dll-ene fra `VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT` (vswhere) til Release-mappen (lov
  etter Microsofts regler for lokal utrulling), og dumpbin `/dependents` sjekker at alt exe-en og dll-ene trenger av
  msvcp/vcruntime/concrt/vccorlib ligger der; hva de ellers henter fra Windows, logges. Den skiller «ved start» (det
  fyrlys.exe henter, og videre) fra «ved behov» (FFI), og stopper bygget hvis noe som lastes ved start trenger
  feilsøkingsutgaven av runtime. Første kjøring (VS 18, MSVC 14.51): fyrlys.exe og de fire programtilleggene trenger
  msvcp140, vcruntime140 og vcruntime140_1. `zlib.dll` (ved behov) er et Debug-bygg som trenger ucrtbased.dll og
  vcruntime140d.dll (finnes bare med Visual Studio): ukjent hvilken pakke den kommer fra, og om appen noen gang laster
  den på Windows. `dartjni.dll` (ved behov) henter jvm.dll.
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
  GitHub-release `vX.Y.Z` («Fyrlys X.Y.Z», blir «Latest»), med `Fyrlys-oppsett.exe`, `Fyrlys-windows.zip` og (når den
  er signert) `Fyrlys-android.apk` (faste navn, så `releases/latest/download/<fil>` alltid er siste versjon; appen
  oppdaterer seg fra zip-fila eller APK-en; releasen venter på både Windows- og Android-jobben; v2.1.10–
  v2.1.11 har også APK-er; artefaktene hentes med navn, actions checkout@v7, upload-artifact@v7, download-artifact@v8), teksten fra CHANGELOG.md og
  byggnummeret skjult som `<!-- bygg N -->` (appen leser det). Finnes releasen alt (samme versjon på nytt), byttes
  filene (andre filnavn slettes først) og teksten. Appen spør `releases/latest`. (Fram til 2.1.9 lå versjonene i
  releasen `testbygg` med byggnummeret i navnet; den er slettet, og reservene for den er fjernet i 2.1.13.)
  Gamle releaser: v0.1.0 (forhåndsutgivelse) og v2.0.0 (andre filnavn, ingen byggnummer) ligger der fortsatt.
  Offentlig repo: Actions-minuttene er gratis; et bygg tar rundt 10 minutter. Bruk `[skip ci]` når en endring
  bare gjelder notater eller README. Versjonen står nederst i menyen (`appBuildLabel`; `--dart-define`
  FYRLYS_VERSION/BUILD/COMMIT/REPO, `lib/build_info.dart`); byggnummeret (`--build-number`) er `github.run_number`. Kjøringer kan avbrytes med `gh run cancel <id> --repo ungerdas/fyrlys`.

## Arkitektur (`lib/`)
- NRK fra NRK (2.1.27, eieren 1.11: «Fyrlys skal kun bruke disse m3u8 fra NRK», og valgte å bygge dem inn for alle):
  `core/public_streams.dart` (`publicStreams`: nrk1/nrk2/nrk3/nrksuper → `…/muxed.m3u8` på NRK sitt CDN;
  `publicStreamKeys(navn)` tar bort land foran og bak («NO: », «|NO|», «[NO]», « NO»), kvalitet («HD», «FHD»,
  «(1080i)», «HEVC») og tegn, og krever at resten er nøyaktig nøkkelen (eller den delte «nrk3super» → nrk3 og
  nrksuper), så regionale NRK1, «NRK 2 Lydtekst», «NRK Tegnspråk» og «NRK1 +1» ikke byttes; `publicStreamKey` = én
  nøkkel; `isPublicStream`). 2.1.28 (eieren: «Burde vi slå sammen da, NRK er en, NRK 2 er en, og NRK 3 er en og NRK
  Super er en?»; leverandøren hans har «NRK 1 HD NO», «NRK 1 FHD NO», «NRK 3/SUPER NO/HD/FHD»): `mergePublicChannels`
  i `Session._applyLists` gjør variantene til én kanal hver der den første sto (NRK Super rett etter NRK3), navn fra
  `publicNames`, id/logo/guide/arkiv fra den beste varianten (FHD > HD > resten > SD, delt sist) som ikke er tatt (NRK3
  og NRK Super får hver sin variant av «NRK 3/SUPER»; er det bare én, får NRK Super `<id>~nrksuper`, og kildene bruker
  `providerChannelId` i open/epg/archive/archiveClip), nummeret fra den første. Én variant som ikke er delt, står
  uendret. Kan kjøres på en sammenslått liste (lista fra sist). Favoritter og «sist sett» på en variant blir den
  samlede (`Session._current`). `XtreamSource.open`/`M3uSource.open` setter NRK sin adresse først og leverandørens etter (reserve
  før bildet har startet, og i Chromecast/multiview som ellers). Guide, logo, favoritter og arkiv er leverandørens.
  Infoen i spilleren: «HLS rett fra NRK». Testet i `public_streams_test.dart` og kildetestene; om adressene virker
  (geoblokkering, CORS for Chromecast) er ikke prøvd herfra (de svarer ikke til økta). Apple TV-appen er ikke endret.
- Android (2.1.26): `platform.dart` (`isAndroid`, kan settes i testene; testene kjører på Linux). `core/android_host.dart`
  (`AndroidHost`: `device`, `multicast`, `casting(tekst|null)`, `install(sti)`, `openUrl`, `share`; gjør ingenting
  utenfor Android, og feil fra kanalen logges). `main.dart` hopper over én-Fyrlys, window_manager og `WindowMemory`, og
  gir `Updater` mappen `getApplicationSupportDirectory()/oppdatering` (den `ApkProvider` leser fra). `WindowFullscreen`
  = systemlinjene (immersiveSticky/edgeToEdge), `landscape(bool?)` holder telefonen på tvers/høykant, `MiniWindow.supported`
  er false. TV-spilleren: på tvers (`_autoFull`, høyde < 500) = fullskjerm uten knapp for å gå ut; fullskjerm-knappen
  snur telefonen (`landscape`), ut igjen = høykant til spilleren lukkes; «Cast til TV» som knapp under bildet når bildet
  er smalt (`_compactNow`, også på Windows); ingen volumglidebryter; lagt bort (`paused`, ikke mens det castes eller
  arkivet/multiview er over) = `_suspended`, strømmen stoppes og åpnes igjen ved `resumed`; stopper castingen mens appen
  er borte, spilles det ikke her før du kommer tilbake (`_inBackground`). Filmspilleren: alltid hele skjermen
  (`_full` false, ingen fullskjerm-knapp), cast-knappen også smalt, «Lyd av» bort når det er smalt, pause når den legges
  bort. mpv-bufferet er mindre (600/300 MiB på disk). `Updater` på Android: `-android.apk`, lastes ned først når du
  trykker «Last ned» (mobildata), `install()` åpner installeringen (første gang åpner Android innstillingen for å
  installere apper, og den må trykkes igjen), `beforeStart` ser at den er installert (`klar.json` med samme bygg →
  «Fyrlys er oppdatert») og rydder. Feilrapporten deles (`shareReport`), systemlinja er «Android: 15 (API 35) · modell».
  Tekster som sier PC/Windows har egne for telefonen (`castNoContact` i `caster.dart`, brannmuren, «Som telefonen»).
  Chromecast: `ChromecastCaster.discover` holder multicast-låsen mens det letes; `_syncService` starter `CastService`
  (forgrunnstjeneste, mediaPlayback, varsel, wifi- og wake-lås, `stopWithTask`) når den er koblet til, og stopper den når
  castingen stopper. Innloggingen lagres ukryptert i appens egne innstillinger på Android (`NoSecretCodec`).
  Testet i `test/android_test.dart` (spillerne på høykant/tvers, livssyklus, casting i bakgrunnen) og
  `updater_test.dart`; ikke prøvd på en ekte telefon: Kotlin-delen, varselet, multicast, installeringen, mpv på Android.
- `core/source.dart` – `TvSource` (`kind` `xtream`/`m3u`, `hasVod`): kilde til kanaler, EPG, strømadresser og
  favoritter. `PlayTarget(urls, localShift:)`. Begge kildene spiller rett fra leverandøren (`localShift: true`).
  TV-arkivet (2.1.14): `archive(channel)` (programmene, `EpgEntry.inArchive`) og `archiveClip(channel, program)` →
  `ArchiveClip(start, stop, urlsAt(from))`, som gir adressene fra et punkt i programmet og hvor strømmen faktisk
  begynner (et helt minutt). `Channel.archiveDays`/`hasArchive` (JSON `arc`). Bare Xtream; M3U har det ikke.
  - `core/xtream_source.dart` – Xtream Codes (port av `xtream.py`): `player_api.php`,
    User-Agent som VLC, strøm `/live/<bruker>/<passord>/<id>.m3u8` og `.ts` som reserve, EPG i base64.
    Innloggingen (2.1.46, eieren 8.11 fikk ikke lagt inn et nytt abonnement, men kanalene kom til slutt): feilene har
    `SourceFailure` (`source.dart`: unreachable/rejected/notXtream/wrongLogin/other). `xtreamResponseProblem`
    (HTTP 400 «plain HTTP request was sent to HTTPS port», Cloudflare-sider, 401/403, 404, tomt svar) og
    `xtreamNotJson` (nettside, ellers «ikke som en Xtream-server"); `decodeJsonLenient` tåler BOM og PHP-advarsler
    foran JSON-en; `xtreamAuthorized` godtar auth 1/«1»/true (uten auth: status Active). Ved rejected/notXtream
    prøves `loginUserAgents` etter tur (VLC, `okhttp/4.12.0`, `Fyrlys`), aldri ved feil passord (sperring for mange
    forsøk); den som virket, står som `ua` i `toPrefs` (bare når den ikke er VLC, så id-en er den samme) og brukes for
    alt (`httpHeaders`). `core/net_problem.dart`: `connectionProblem` (navnet finnes ikke, 111/61/10061/1225
    avvist, 110/60/10060/121 tidsavbrudd, ingen rute, https mot en http-port, sertifikat; uten vertsnavnet, fordi
    `scrub` bare tar vertsnavn i adresser og meldingen kan havne i loggen og feilrapporten), `closedByServer` (en
    forbindelse som lukkes uten svar regnes som avvist, nginx «444»), `errorKind` til loggen (aldri adressen:
    `_ClientSocketException.toString()` har hele adressen med brukernavn og passord). `_api` logger feil (ikke for
    `get_short_epg`/`get_simple_data_table`, som hentes for mange kanaler). `Session.loginM3u`: unreachable fra
    Xtream-forsøket kastes med en gang (lista ligger på samme sted), og feiler lista også, vises Xtream-feilen når den
    var wrongLogin eller rejected.
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
  det gamle brukes når nettet feiler, 404 huskes i 10 min, `prune()` ved start holder det under 300 MB; 2.1.45: høyst
  `parallel` 8 nedlastinger samtidig, resten venter med de nyeste først, og de eldste over `maxWaiting` 200 gis opp
  uten å regnes som feil). Settes opp i
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
  på Hjem alle kanalene), `ui/channel_card.dart` (`showNext`: også det som kommer etterpå; 2.1.40, eieren 4.11 med
  bilde av eventkanaler: «Forbedre gjerne så navnene ikke kuttes»: navnet på to linjer når det ikke står et program
  under (eventkanalene, og kanaler uten program nå; til programinfoen er hentet: én linje), nummeret over stjerna
  (kompakt), hele navnet som verktøytips etter 800 ms; høyden er den samme, 84; det samme i kanallista i spilleren,
  `_details` i `side_list.dart`).
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
  den innloggingen via `Session.favoritesOf`, ellers alle, med søk; fra 2.1.45 `ChannelPicker` i
  `ui/channel_picker.dart`, eieren 8.11: «tror vi må samle i mapper som det ser ut når man velger kanaler til vanlig,
  den krasjet nå når jeg prøvde»: mappene `mappe:<fav|recent|all|kategori>` som sidemenyen på TV-siden, kanalene
  `kanal:<id>` bare i mappen som er åpen, søk i alle med høyst `pickerSearchLimit` 300 treff (merknad øverst), smalt
  vindu (< 640) mappene først og `til-mappene`; lista per innlogging én gang per side (`_listsFor` →
  `Session.listsOf`: den i bruk, ellers `listCache` fra sist, ellers kilden; `recentOf`, `favoriteCategoriesOf`)),
  1–4/piler, M, F, Esc. `Session.canMultiview` (to
  innlogginger, eller `_connections` ≥ 2 fra `account()` etter `_attach`) styrer knappen «Multiview» i toppen av
  TV-siden (med kanalen du så sist) og i spilleren (V; `_away` stopper direktesendingen og tar kanalen med,
  `startFull`). Testet i `multiview_test.dart`; fire mpv-er samtidig i ekte bruk er ikke prøvd.
- `ui/archive_page.dart` (2.1.14) – TV-arkivet for én kanal: programmene nyeste øverst, dag for dag (`archiveDay`:
  I dag / I går / «Lørdag 24. oktober»), «Går nå», «Ikke i arkivet» dempet, strek for det du har sett. Et trykk lager
  `VodPlayItem`-er for alle som kan ses (`archiveItems`/`archivePlayItem`, nøkkel `arkiv:<kanal>:<start>`) og åpner
  filmspilleren på det valgte.
- `ui/vod_browser.dart` (2.1.35, eieren 3.11 med skjermbilde fra en annen IPTV-app: «Ønsker litt denne stilen på
  serier fanen»; gjelder også Filmer: oversikten (`_view` '') med rader bortover: «Fortsett å se» som brede kort
  (`_WideContinueCard`: `ContinueItem.backdrop` eller uskarp plakat, hvit strek `_ArtProgress`, ♡ og ×), «Favoritter»
  (`Session.vodFavorites`/`toggleVodFavorite`, `vod_favorites@<innlogging>`, `VodItem.toJson`), «Nylig lagt til»
  (`VodSort.newest`) og én `_LoadedRow` per kategori, med «Vis alle»; knappen øverst (`_Pill`, meny med Oversikt/Alle/
  kategoriene) og søket gir rutenettet (`_view` 'alle' eller en kategori), med sortering og tilbake-pil. Backdrop:
  `VodItem.backdrop` (serier: `backdrop_path` i lista) og `withBackdrop`, i `ContinueItem` fra detaljene. Før 2.1.35:
  plakater i rutenett, kategori, sortering, sider hentes når du er 30 fra slutten, søk
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
  byttes ut i testene for sider som lager avspilleren selv). Feil (2.1.22): `errorStream` er ikke media_kits
  `stream.error`, men lages fra `stream.log` (`PlayerConfiguration(logLevel: MPVLogLevel.warn)`) med
  `mpvErrorIsFatal`: bare `error` fra cplayer/stream/file og ffmpeg `tcp:`. media_kit gir også vd/ad-feil
  («Error while decoding frame!») som feil, og de kommer i starten av opptak fra TV-arkivet, som begynner midt i en
  TS-pakke (et par hundre byte før første 0x47) og midt i en GOP; da ga spillerne opp (eieren 27.10: «Failed to
  recognize file format» på «Se fra start»; en test mot leverandøren viste at både .m3u8 og .ts virker i mpv på Linux,
  og at tidssonen i adressen stemmer). Alle advarsler og feil fra mpv går i loggen (samme melding høyst hvert 30. s).
  Fullskjerm for begge spillerne:
  `WindowFullscreen` i `ui/window_effects.dart`. Språk: `setLanguages` setter `alang`/`slang` og
  `subs-with-matching-audio=no` når undertekstspråk er valgt; ved ny adresse settes `aid=auto` og `sid=auto`/`no`
  (et spor valgt for hånd står ellers i mpv til neste fil; samme adresse, f.eks. etter spoling, beholder det).
  `tracks()` leser `aid`/`sid` fra mpv (media_kit vet bare om spor valgt via `setAudioTrack`). Bildeundertekster
  (PGS/DVB) vises ikke: media_kit tegner tekstundertekster selv (`sub-visibility=no` uten libass).
  «Fjern striper» (2.1.31): `setup(live:)` eller `setup(tv:)` (multiview) = TV-bilde (`_tv`), og da setter
  `setPicture` `deinterlace=no` og `vf` = `MpvPlayback.tvDeinterlace` (`format=fmt=yuv420p` henter maskinvaredekodede
  bilder fra skjermkortet, så `bwdif=mode=send_frame:deint=interlaced`: ett bilde per bilde, bare interlacede bilder);
  mpv sin egen (`deinterlace=auto`, ett bilde per halvbilde, 50 fra 1080i50) brukes for filmer og som reserve når `vf`
  ikke tar imot kjeden. Infoen: «(fjerner striper)», eller «(interlacet)» om bwdif ikke virker. CI-steget «Sjekk
  avspilleren» spiller en liten interlacet y4m-fil med ekte libmpv og krever 20–30 bilder/s og ikke interlacet med
  kjeden (leser strengen fra playback.dart); mpv sin egen og uten deinterlacing logges til sammenligning. Ikke på Android.
  2.1.39: `VideoControllerConfiguration(hwdec: 'auto-copy')` på PC (media_kits standard er `auto`): med d3d11va rett
  fra skjermkortet ble hele dekoderflaten tegnet (for HEVC rundet opp til 128 linjer, 816 → 896), så filmen ble klemt
  sammen med en grønn stripe nederst (eieren 4.11, bilde fra en PC med Intel-grafikk; ikke på den andre PC-en).
  `ytdl=no` i `setup` (mpv prøvde youtube-dl på hver adresse som ikke kunne åpnes).
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
  flytting/endring, ikke i fullskjerm eller minimert (maksimert beholder den vanlige størrelsen). 2.1.38 (eieren 4.11:
  «Fyrlys hopper alltid minimert», med skjermbilde av et vanlig vindu): Flutter-programmet viser vinduet med
  `ShowWindow(SW_SHOWNORMAL)` når første bilde er tegnet (`win32_window.cpp` fra `flutter create`), og det gjorde
  et vindu som var maksimert før det, vanlig igjen; `onWindowUnmaximize` lagret det, så det ble vanlig hver gang.
  Nå maksimeres det først når det er vist (`_maximizeWhenShown`: `isVisible` hvert 40. ms, høyst 20 s, så
  `maximize` uten animasjonen), og ingenting lagres imens (`_waiting`); `ready` er ferdig når det er gjort.
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
  uventede feil, satt opp i `main.dart`; 2.1.45: på PC også i `<support>/logg.txt` (`attach` etter én-Fyrlys-sjekken,
  hver linje skrives med en gang, begynner på nytt over 1 MB), `closed()` skriver `closedLine` når appen avsluttes
  (`didRequestAppExit`, «Start på nytt nå»), og mangler den ved neste start, står de 150 siste linjene i
  `previousRun` og i rapporten under «Forrige gang Fyrlys kjørte (ble ikke avsluttet som vanlig)»; ikke på Android,
  der stoppes appen uten å få vite det; `scrub` fjerner vertsnavn, IP, `/live|movie|series|timeshift/<bruker>/<passord>`,
  `username=`/`password=`, e-post og `C:\Users\<navn>`), `core/report.dart` (`buildReport`: versjon, Windows, antall og
  slag innlogginger (ikke navnene), abonnementet, listene, innstillingene, loggen og slutten av oppdateringsloggen;
  `saveReport` i Nedlastinger, `showInExplorer`, `openUrl` byttes ut i testene; `openUrl` på Windows er `shellOpen` i
  `core/shell_open.dart` (2.1.36: ShellExecuteW med FFI i en egen isolate, COM satt opp rundt; explorer.exe åpnet
  Dokumenter for Plex-adressen med «#?» og «&»); `windowsName` (2.1.25): Windows 11 sier
  selv «Windows 10» i `Platform.operatingSystemVersion`, så bygg ≥ 22000 gir «Windows 11»). Innstillinger → Hjelp →
  «Feilrapport» åpner `ui/report_page.dart` (2.1.30): hele teksten (`SelectableText`, nøkkel `report-text`), «Kopier»
  (`copyText`, byttes ut i testene) og «Del feilrapport» (Android) / «Lagre feilrapport» (PC). Rapporten har `\n`;
  `saveReport` skriver `\r\n` (Notisblokk). Grunnen (feilrapport 1.11): delt fra telefonen kom bare begynnelsen fram,
  og resten uten linjeskift. Skjemaene for GitHub-saker ligger i `.github/ISSUE_TEMPLATE` (feil, ønske).
- Chromecast (2.1.24, eierens ønske «Lag en egen versjon ja!»): `core/cast/` – `mdns.dart` (`discoverCastDevices`:
  PTR-spørsmål etter `_googlecast._tcp.local` fra en tilfeldig port på hvert nettverkskort og en lytter på 5353,
  `parseCastResponse` med navnepekere, TXT `fn`/`md`/`id`, SRV-porten, A-posten eller avsenderen), `cast_protocol.dart`
  (CASTV2: protobuf-meldingen CastMessage kodet for hånd, fire byte lengde foran, `CastFrameReader`),
  `chromecast.dart` (`CastConnection`: TLS 8009 med selvsignert sertifikat (`chromecastSocket`, en vanlig socket i
  testene), PING/PONG, `request` med requestId; `ChromecastCaster`: CONNECT, LAUNCH av Googles avspiller
  `CC1AD845` (Default Media Receiver), CONNECT til transportId, LOAD med `contentId` fra mellomstasjonen, `LIVE`/
  `BUFFERED`, `hlsSegmentFormat: ts` for HLS, uten `currentTime` for direktesendinger (2.1.25; 0 er det eldste
  segmentet i lista), MEDIA_STATUS → `CastState`, PLAY/PAUSE/SEEK, SET_VOLUME, STOP; RECEIVER_STATUS uten vår økt =
  stoppet på TV-en; ERROR/LOAD_FAILED med `detailedErrorCode` → `_errorText` (102/110 bilde/lyd, 104/316 format,
  103/30x/31x nettet, ellers koden), også når koden kommer etter IDLE med ERROR; tilstandene og feilene logges),
  `cast_proxy.dart` (`CastProxy`: HttpServer på en ledig port,
  adresser `http://<PC-ens adresse mot Chromecasten>:<port>/<tilfeldig merke>/<løpenr>/strom.<ext>` så Chromecasten
  aldri ser brukernavn/passord; henter med kildens hoder (User-Agent), sender videre med CORS (Googles avspiller
  krever det for HLS, leverandørene har det ikke), skriver om spillelister (`rewritePlaylist`, også `URI="…"`), går
  rett til der en spilleliste ble videresendt neste gang, Range videre for filmer; `requests` = 0 etter en feil gir
  beskjeden om Windows-brannmuren. 2.1.25: en adresse som én gang var en spilleliste, skrives alltid om
  (`_Entry.playlist`), ellers kjennes den på type, .m3u8 eller `startsLikePlaylist` (#EXTM3U først); siste ledd i
  adressen må stemme (`_Entry.name`), så et relativt segment som ikke ble skrevet om gir 404 og en linje i loggen.
  Loggen (`_note`, samme beskjed høyst hvert 10. s): `describePlaylist` første gang (segmenter, mål, varianter med
  CODECS, ENDLIST, fMP4, kryptering; aldri adressene), svar ≥ 400 fra leverandøren, og hvert 20. s hva Chromecasten
  har hentet, eller at den har sluttet) og `caster.dart` (`Caster` med `CastState`/`CastItem` (HLS foretrekkes,
  `contentType` etter filen), og `appCaster`, én for hele appen; testene bytter den med `FakeCaster` i `fakes.dart`).
  `ui/cast_ui.dart`: `pickCastDevice` (dialogen, «Let igjen»), `CastPanel` (vises i stedet for bildet: hvor, hva,
  tilstand, pause, volum på TV-en, «Stopp casting»; `leading` for kanal-/spoleknapper), `CastProgress` (tidslinja for
  filmer), `CastBar` (nederst på forsiden når spilleren er lukket). TV-spilleren: cast-knappen (ikke i smalt vindu),
  `_startCast` stopper mpv (én tilkobling), `_open` sender kanalen til TV-en mens `appCaster.active` (`_castLoad`),
  `_onCast` spiller her igjen når castingen stopper (ikke mens `_connecting` eller `_visiting`, dvs. arkivet over),
  `ended` → `_ended` (nye forsøk), `failed` → kortet med «Prøv igjen»; tastene i `_onCastKey`; ikke multiview mens
  det castes. Filmspilleren: `_castOpen` (arkivet: fra minuttet, som her; spoling i arkivet åpner på nytt, ellers
  SEEK), `_castTimer` holder `_position` oppdatert for «fortsett der du slapp», `ended` → `_onEnd` (neste episode),
  og når castingen stopper, fortsetter den her der TV-en var. Testet i `cast_test.dart` (meldingene, mDNS-pakker,
  spillelister, mellomstasjonen mot en lokal leverandør, `ChromecastCaster` mot en falsk Chromecast over en vanlig
  socket) og `cast_ui_test.dart` (spillerne og linja med `FakeCaster`). Ikke prøvd mot en ekte Chromecast:
  oppdagelsen på Windows (5353 og brannmuren), om Googles avspiller godtar http fra PC-en, `hlsSegmentFormat`, og
  hvilke kanaler den faktisk spiller.
  2.1.30 (feilrapport fra telefonen 1.11: en MKV-film ga IDLE, LOAD_FAILED og IDLE (ERROR) i samme sekund, uten kode og
  uten én forespørsel til mellomstasjonen, tre ganger på rad; på TV-en: «feil i strømmen»): `CastItem.contentTypes` i
  den rekkefølgen de prøves (MKV: `video/mp4`, `video/webm`, `video/x-matroska`; HLS: `application/x-mpegurl`, så
  `application/vnd.apple.mpegurl`), `format` («MKV», «HLS»), `details`/`risky` fra `MediaTech.summary`/`castRisks`
  (`VodPlayItem.tech`: filmens fra `movieInfo` på detaljsiden, episodenes fra get_series_info). `ChromecastCaster`:
  `_sendLoad` (LOAD med `nextRequestId()`, `_loadId`, `_awaitingLoad` til et svar med det requestId-et kommer; feil
  imens hører til en LOAD som er gitt opp), `_attemptFailed` (LOAD_FAILED, INVALID_REQUEST på `_loadId`, IDLE med
  ERROR): ingen forespørsler og ikke spilt → neste type, ellers `failed` med `_failureText` (koden; ellers «avviste … uten
  å hente noe», «kunne ikke spille filen (MKV) …» + «Filen har {codecs} …», «stoppet avspillingen» når den hadde
  spilt; `_unreachableText` bare når LOAD ikke svarer). IDLE oppdaterer ikke posisjonen (0), så «Prøv igjen» begynner
  der du var. Feilmeldingene logges hele (`_brief`). Mellomstasjonen: `add(main: true)` for det som er i LOAD; for en fil
  logges de 12 første forespørslene («fil 0: GET fra 1,2 GB → 206 (video/x-matroska, 812 MB)»), og om leverandøren
  brøt forbindelsen eller Chromecasten lukket den. `CastPanel(message:, onRetry:)`: beskjeden står i panelet og «Prøv
  igjen» (`cast-retry`) i stedet for pauseknappen; spillerne legger ikke lenger et kort oppå panelet (eieren 1.11:
  skjermbilde der de lå oppå hverandre). Om MP4-typen får Chromecasten til å spille MKV-filer, er ikke prøvd.
  2.1.32, den egentlige feilen (feilrapport 2.11: en TV-kanal fra telefonen ga LOAD_FAILED etter 3 s, igjen uten én
  forespørsel): `CastConnection.localAddress` var `_socket.address`, og for en socket vi åpner selv er det adressen det
  ble koblet *til* (Dart: `_NativeSocket.normal(address)` med den oppslåtte fjernadressen), altså Chromecastens. URL-ene
  til mellomstasjonen pekte på Chromecasten selv. Nå `local_address.dart`: `localAddressFor(host)` velger blant
  `NetworkInterface.list` den adressen som har flest bits felles med Chromecastens (`pickLocalAddress`,
  `commonPrefixBits`; ikke loopback, link-local bare mot link-local), `chromecastSocket(host, port, source)` kobler til
  fra den (`Socket.connect(sourceAddress:)` + `SecureSocket.secure`; går det ikke, velger systemet), og loggen sier hvor
  mange bits den har felles med Chromecasten (adressene vaskes bort). `ChromecastCaster(localAddress:)` i testene;
  testen «Chromecasten får adressen her …» bruker 127.0.0.2. Hentet den ingenting med noen av typene, vises
  `_unreachableText` (brannmuren på PC-en, samme wifi på telefonen). Ikke prøvd mot en ekte Chromecast.
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
- Plex (2.1.34, eieren 3.11: «Plex fane eller noe, som erstattet Filmer/Serier hvis man ville å koble til Plex. Gjerne
  litt som Plezy»; Plezy er GPL-3, så ingen kode derfra, bare API-fakta). `core/plex/`: `plex_models.dart` (`PlexServer`
  fra plex.tv `resources` (bare `provides` server, uten IPv6) og `fromSaved`, `PlexConnection` med `tier` 0 hjemmenett/1
  nett/2 relay og `lanHttp` (http til en privat adresse i hjemmenettet når …plex.direct stoppes av ruteren; aldri over
  nettet), `PlexLibrary` (movie/show), `PlexItem` (film/serie/sesong/episode: bilder, `viewOffset`/`viewCount`/
  `leafCount`, `onDeck` (ett objekt i `OnDeck.Metadata`), `media`/`part`/`streams`, `markers` (`final` = rulleteksten
  på slutten), `tech` → `MediaTech`, `resumeAt` via `resumeFrom` (≥ 10 s, ≤ 95 %), `logo` (2.1.44, eieren 6.11 om
  detaljsiden: «vil også ha Serie/Filmlogo også hvis det er tilgjengelig»: `plexLogo` = `clearLogoWide`, ellers
  `clearLogo` fra `Image` i metadataen)), `PlexSort` (serier: «nylig lagt til» = `episode.addedAt:desc`)), `plex_api.dart` (`PlexClientInfo`: hodene
  X-Plex-Product «Fyrlys», fast `X-Plex-Client-Identifier`, enhetsnavn i ASCII, `X-Plex-Language` nb/en (2.1.37: for
  overskriftene serveren lager selv; om den oversetter til nb, er ikke prøvd); `PlexTv`: PIN med `strong=true`,
  `authUrl` (app.plex.tv/auth), `checkPin`, `userName`, `servers` (clients.plex.tv); `pickConnection`: alle adressene
  prøves samtidig mot `/identity` uten nøkkelen (krever samme machineIdentifier), beste i laveste tier, https foran
  http; `PlexServerApi`:
  biblioteker, `items` (sider med X-Plex-Container-Start/Size, `genre`), `genres`, `continueWatching`
  (`/hubs/continueWatching/items`, ellers `/library/onDeck`), `recentlyAdded`, `metadata` (`includeOnDeck`,
  `includeMarkers`), `children`, `related`, `search` (`/hubs/search`, bare film/serie/episode, `sectionId`),
  `setWatched` (`/:/scrobble`/`unscrobble`), `timeline`, `image` (`/photo/:/transcode`, nøkkelen i adressen), `logo` (stien som den er, med nøkkelen: omkodingen
  kan gjøre gjennomsiktige PNG-er om til JPEG),
  `homeHubs` (2.1.37: `/hubs/promoted` med `contentDirectoryID` og `pinnedContentDirectoryID` = bibliotekene som
  vises, `count=20`, `excludeContinueWatching=1`; `parseHubs` i plex_models: rekkefølgen fra Plex, bare film/serie/
  sesong/episode fra bibliotekene som vises (hubens og hvert elements `librarySectionID`), uten hubIdentifier med
  continue/ondeck; `PlexHub.canShowAll` = `more` og en `key` som begynner med /), `hubItems` («Vis alle»: `key`
  med X-Plex-Container-Start/Size, `PlexHubPage` med `fetched`/`total`),
  `file` (nøkkelen som hode), `stream` (undertekstfiler); `PlexTv.homeUsers` (`clients.plex.tv/api/v2/home/users`) og
  `switchUser` (POST `…/home/users/<uuid>/switch` med kontoens innlogging og `pin`; 403 med feilkode 1041 eller uten
  kode = PIN-koden mangler eller er feil, `PlexException.pin`; svaret har `authToken`); `PlexHomeUser` i
  plex_models (friendlyName, ellers title), `plex_account.dart` (`PlexAccount` i `Session.plex`, felles for
  alle IPTV-innloggingene: kryptert i `plex_protected` (ellers `plex_plain`), `plex_client_id`, `plex_replace_vod`
  (på), `plex_hidden_libraries` (2.1.37, eieren 4.11: «vil ha mulighet til å ta vekk» biblioteker; «<server>/<nøkkel>»;
  `isHidden`, `setHidden`, `shownLibraries`, `shownSections`), `plex_library_order` (2.1.41, eieren 5.11: «Ønsker
  muligheten til å endre på rekkefølgen her» om sidemenyen; hele rekkefølgen for serveren, «<server>/<nøkkel>», andre
  serveres står igjen; `libraries` sorteres med `_inOrder` i `_connect`, nye biblioteker sist; `moveLibrary(l, step)`
  ett steg blant alle, også de skjulte; pilene bare i valget av biblioteker, eieren 5.11 om pilene i sidemenyen i
  2.1.41: «ønsker ikke knappene synlig hele tiden, kun når jeg går inn på innstillinger i høyre hjørne»); Plex Home
  (2.1.43, eieren 5.11: «jeg har plex home og vil da gjerne kunne velge hvem som skal se på»): `_token` er
  innloggingen til den som ser på, `_homeToken` kontoen som koblet til (lagret som `home` når de er ulike), og med den
  hentes og byttes brukerne (`loadHomeUsers`, én gang per kjøring med `ensureHomeUsers` fra Plex-fanen og
  innstillingene, og etter `signIn`); `switchUser(u, pin:)` henter brukerens innlogging, så serverne med den (samme
  server når brukeren har tilgang; hver bruker har sin egen nøkkel på serveren, med sin «Fortsett å se» og det den har
  sett), og lagrer `homeUser`; `currentHomeUser` (valgt, ellers kontoens brukernavn, ellers admin), `hasHome` (flere
  enn én), `askUser` (`plex_ask_user`, av) og `askedThisRun`; navnene logges ikke, rapporten har bare antallet;
  `connect` (adressen fra sist først når den var i hjemmenettet, så `pickConnection`, så serverlista fra plex.tv
  på nytt; delt forsøk, `_gen` ved bytte; `_api` byttes først når det nye svarer), `run` (ny adresse og ett nytt
  forsøk når forbindelsen brøt, felles for alle som feilet samtidig), `reportLine` og loggen uten servernavn/
  adresser (`_errorKind`; `error` i appen har navnet); `PlexReporter`: timeline playing/paused/stopped, og `/:/scrobble` bare når serveren ikke har sett deg gå
  forbi 90 % selv). `core/play_info.dart`: `PlayReport`, `PlayExtras`, `ExternalSubtitle`, `SkipMarker`. `VodPlayItem`
  har `headers`, `startAt`, `report`, `extras`, `explain`; `VodPlayerPage.more` (neste sesong, hentes når siste episode
  begynner); spilleren sender framdrift til `report` i stedet for `saveResume` (`_save(stop:)`), husker posisjonen i
  `_seenHere`, sender ingenting etter «stoppet» (`_closing`: mpv sier «pause» når den stoppes), legger undertekstfilene
  til med `Playback.addSubtitles` (mpv `sub-add`, `<key>.<filtype>?encoding=utf-8`; den på språket du foretrekker velges
  når filen selv ikke har valgt noen) og viser «Hopp over introen (S)» / «Hopp over rulleteksten (S)» / «Neste episode
  (S)» for rulleteksten på slutten (episoden meldes som sett først) (`hopp-over`). `ui/plex/`:
  `plex_view.dart` (fanen: sidemeny/nedtrekksliste med de som vises og `velg-biblioteker` (tune) ved overskriften,
  bibliotek med sjanger/sortering og sider à 100, søk uten skjulte biblioteker; Hjem (2.1.37, eieren 4.11 med bilder
  av Plex: «Hjem siden på plex er som hjem siden på orgianle plex. Med "Nytt fra ..." radene»): «Fortsett å se»
  (uten skjulte biblioteker), så radene fra `homeHubs` (kort `rad:<hubId>:<ratingKey>`, «Vis alle» `vis-alle:<hubId>`
  åpner `_PlexHubPage` med kortene `alle:<ratingKey>`); svarer serveren 404/400 eller har ingen rader, «Nylig lagt
  til i …» per bibliotek (`nylig:<bibliotek>:<ratingKey>`, «Vis alle» velger biblioteket); nøkkelen til Hjem og søket
  har bibliotekene som vises, i rekkefølgen, så de hentes på nytt når noe skjules eller flyttes (`homeHubs` sender
  dem i den rekkefølgen; om Plex ordner radene etter den, er ikke prøvd); flisene i sidemenyen `sidemeny:<id>`, uten
  piler; `velg-biblioteker` har verktøytipset «Velg og sorter biblioteker»; `_refresh` henter på nytt når du kommer tilbake), `plex_detail_page.dart` (film: `DetailHero` fra
  `vod_detail_page.dart` (med `logo`, bare i mørkt utseende: `_HeroLogo` (`hero-logo`) viser navnet til logoen er
  lastet og når den feiler, så logoen innenfor 460 × 130 nede til venstre, med navnet som verktøytips), Spill av/Fortsett/Fra begynnelsen, sett/ikke sett, «Mer som dette»; serie: sesongene sortert,
  episodene, «Fortsett SxxEyy» fra OnDeck, meny per episode), `plex_play.dart` (`plexPlayItem`, `plexExtras`,
  `plexExplain` (HTTP-koden), `plexNextSeasons` (sesong 0 hoppes over), `openPlexPlayer`, `playPlexItem`),
  `plex_login.dart` (PIN-dialogen: åpner nettleseren, sjekker hvert 2. s; serverlista; `showPlexLibraries`, ListTile med
  avkrysning `vis-bibliotek:<nøkkel>` og pilene `flytt-opp:<nøkkel>`/`flytt-ned:<nøkkel>` (`plexMoveButton` i
  `plex_widgets.dart`, som «Dine kategorier» på TV-siden), kobler til først når bibliotekene ikke er hentet), `plex_widgets.dart` (`PlexRow` med
  `onAll`/`allKey`), `plex_users.dart` (2.1.43: `showPlexUsers` = «Hvem ser på?» med `plex-bruker:<uuid>`, PIN-feltet
  `plex-pin` (fire siffer byttes med en gang, `readOnly` mens det byttes), `PlexAvatar`); Plex-fanen har den som ser
  på øverst i sidemenyen (`hvem-ser-pa`, også ved nedtrekkslista) når `hasHome`, og nøkkelen til sidene har
  `homeUser`; Innstillinger → Plex: «Bruker i Plex Home» (`bytt-plex-bruker`) og «Spør hvem som ser på når
  Plex-fanen åpnes».
  `home_page.dart`: `_Section.plex`; Filmer/Serier skjules når Plex erstatter dem. Innstillinger → Plex (koble til/fra,
  bytt server, «Plex erstatter Filmer og Serier»). Testet i `plex_test.dart` og `plex_ui_test.dart` med en falsk
  Plex-server (`plex_fake.dart`); ikke prøvd mot en ekte Plex-server: PIN-innloggingen, adressevalget (plex.direct,
  relay), at mpv spiller filene med hodene, timeline/scrobble, markørene og undertekstfilene.
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
- 27.10.2026: 2.1.23 (eierens valg: «Bytt til full mpv»): workflowen bytter `libmpv-2.dll` fra media_kit (bygget
  20241021 fra media-kit/libmpv-win32-video-cmake: FFmpeg med bare filtrene overlay og equalizer, så ingen
  deinterlacer, og mpv uten `deinterlace=auto`) med `mpv-dev-lgpl-x86_64-*.7z` fra zhongfly/mpv-winbuild (tag i
  `MPV_TAG`, sha256 fra releasens sha256.txt). Releasene der ryddes bort etter en tid, så første bygg på main legger
  arkivet i Fyrlys sin egen forhåndsrelease `libmpv-<tag>` (ikke «Latest»), og senere bygg henter det derfra. Steget
  «Sjekk avspilleren» laster dll-en med ctypes og sjekker `deinterlace=auto` og `vf add bwdif`. Ny tag: bytt
  `MPV_TAG` (ny kopi lages av seg selv). LGPL: dll-en er dynamisk lenket og kan byttes; nevnt nederst i README.
- 27.10.2026: 2.1.22: TV-arkivet ga opp på grunn av dekoderfeil i starten (se `ui/playback.dart`). Eieren 27.10:
  «Tror det fungerte» (feilrapport: et program fra arkivet kom i gang etter ca. 10 s). Samme feilrapport viste at
  mpv-en i media_kit ikke kan `deinterlace=auto` («Invalid parameter for deinterlace flag: auto») og ikke har lavfi-
  filteret `yadif` («filter 'yadif' not found»), så «Fjern striper» virker ikke (ikke rettet ennå; mulig vei:
  `deinterlace=yes` og maskinvarens `d3d11vpp`). Ellers i loggen: «property not found _setProperty(osc, 1)» og
  «dxva2-egl: Failed to create EGL surface» fra media_kit (ufarlig så langt).
- 31.10.2026: 2.1.24: Chromecast (se Arkitektur). Bare testet med tester.
- 31.10.2026: 2.1.25: første forsøk med Chromecast hos eieren (feilrapport fra 2.1.24): koblet til,
  mellomstasjonen startet, kanalen ble sendt til TV-en og 8 s senere åpnet på nytt; loggen sa ikke hvorfor. Rettet
  det som kan ha vært årsaken (`currentTime` 0 for direktesendinger, spillelister som bare ble kjent igjen første
  gang) og lagt inn logging av hva TV-en og mellomstasjonen gjør. Leverandørens spilleliste har typen
  `application/x-mpegurl` («mime type is not rfc8216 compliant» fra mpv), som ble kjent igjen også før. Eieren
  rettet også at rapporten sa Windows 10 (han har Windows 11).
- 1.11.2026: 2.1.26: Android-telefoner tilbake (se Arkitektur), med Chromecast. Eieren laget nøkkelen (PKCS12, alias
  `fyrlys`) og la inn hemmelighetene; første forsøk var ikke gyldig base64 (innlimt feil), og signeringssteget sier nå
  hva som er galt (base64, passord eller alias) og tåler linjeskift, certutil-linjer og base64url. Kjøringen ble startet
  for hånd (`workflow_dispatch` på main lager også releasen). `Fyrlys-android.apk` (ca. 60 MB) ligger i v2.1.26.
  Ikke prøvd på telefonen hans ennå.
- 1.11.2026: 2.1.27: NRK1–3 og NRK Super fra NRK sine egne strømmer (se Arkitektur). Leverandørens strøm er reserven
  (eieren 1.11: «IPTV skal være reserve. vil bruke strømmen fra NRK»). Kjente ikke igjen leverandørens navn med land
  bak («NRK 1 HD NO») og den delte «NRK 3/SUPER»; rettet i 2.1.28 sammen med sammenslåingen.
- 1.11.2026: 2.1.29: eieren prøvde APK-en i BlueStacks («N32», Nougat 32-bit) og fikk et hvitt vindu: APK-en hadde
  libflutter bare for arm64, men libmpv for armeabi-v7a/arm64/x86_64, så Android valgte armeabi-v7a uten Flutter. Nå er
  alle tre med; `main` viser feilen (`_StartupError`) når noe stopper før `runApp`, loggen har `Abi.current()` og
  `device` har `Build.SUPPORTED_ABIS`. «Får ikke hentet M3U-lista» på Android: venter på hvilken liste og en
  feilrapport (appen logger ikke årsaken ennå; mulig forbedring: tidsavbrudd/sertifikat/ukjent vert i meldingen).
- 1.11.2026: 2.1.30: Chromecast fra telefonen med en film i MKV feilet (se Chromecast under Arkitektur), og boksen med
  feilen lå oppå panelet. Feilrapporten fra telefonen kom bare delvis fram når den ble delt; nå vises den i appen
  med «Kopier». Samme rapport: mpv på Android kjenner ikke `deinterlace=auto` og har ikke `yadif` («Fjern striper»
  skjules der, `setPicture` lar den være), og filmer logget «Failed to create file cache» (nå `cache-on-disk=no` for
  filer). Leverandørens strøm til telefonen brøt én gang («Software caused connection abort», så «Connection refused» i
  noen sekunder) da appen ble lagt bort; forventet uten forgrunnstjeneste.
- 1.11.2026: 2.1.31: eieren: «Fjerne striper på windows appen fungerer heller ikke, video blir bare speedet opp». mpv
  sin egen deinterlacing gir alltid ett bilde per halvbilde (`f_auto_filters.c`: bwdif `send_field`, d3d11vpp med
  felter), altså 50 bilder/s fra 25i; tolket som at det så ut til å gå fortere. Nå ett bilde per bilde i TV (se
  `ui/playback.dart`). CI med ekte libmpv (mpv v0.41.0-1308, testfil 25i): uten deinterlacing 25 bilder/s interlacet,
  mpv sin egen 50 bilder/s, kjeden 25 bilder/s uten striper. Om bildet faktisk gikk fortere enn lyden, er ikke
  avklart (spurt).
- 2.11.2026: 2.1.32: Chromecast fikk Chromecastens egen adresse til mellomstasjonen (se Chromecast under Arkitektur);
  det forklarer alle forsøkene fra 2.1.24 (PC) og 2.1.26 (telefonen). Telefonen hans hadde fortsatt 2.1.28 (2.1.31
  tilgjengelig, ikke installert).
- 3.11.2026: 2.1.33: Fyrlys startet ikke på en annen PC («MSVCP140.dll ikke ble funnet»): Flutter-bygget lenker mot
  Visual C++-runtime, som ikke fulgte med. Nå i programmappen (se Arbeidsmåte, Windows). Den PC-en må installere med
  `Fyrlys-oppsett.exe` (eller Microsofts `vc_redist.x64.exe`), den gamle versjonen starter ikke og kan ikke oppdatere seg.
- 3.11.2026: 2.1.34: Plex-fane som erstatter Filmer og Serier (se Arkitektur). Bare testet med tester og en falsk
  Plex-server.
- 3.11.2026: 2.1.35: Serier og Filmer som oversikt med rader og favoritter (se `ui/vod_browser.dart`). Testet med
  widget-tester.
- 4.11.2026: 2.1.36: «Koble til Plex» åpnet mappen Dokumenter (skjermbilde fra eieren): `openUrl` startet
  explorer.exe med adressen. Nå ShellExecuteW (se Feilrapport under Arkitektur). Ikke prøvd på Windows herfra. Eieren
  fikk koblet til før 2.1.36 var ute (trolig med «Kopier lenken»): «Liker egen Plex fane».
- 4.11.2026: 2.1.37: Hjem i Plex-fanen med radene fra Plex sin egen startside, og biblioteker kan skjules (se Plex
  under Arkitektur). Testet med tester og den falske Plex-serveren; om serveren hans gir «Nytt fra …»-radene i
  `/hubs/promoted` med `pinnedContentDirectoryID`, og om overskriftene blir norske, er ikke prøvd.
- 4.11.2026: 2.1.38: vinduet åpnet alltid som et vanlig vindu, også når det var maksimert sist (se
  `ui/window_memory.dart`). Testet med en test som etterligner window_manager; ikke prøvd på Windows.
- 4.11.2026: 2.1.39: grønn stripe nederst i en film fra Plex (1920×816) på en av PC-ene (se `ui/playback.dart`);
  målt på bildet var filmen klemt omtrent 816/896 og stripa omtrent 80 av 896 linjer. Ikke prøvd på Windows herfra.
  Samme feilrapport: en annen film fra Plex svarte 404 på selve fila (Plex finner den ikke på disken).
- 4.11.2026: 2.1.40: navnene på kanalkortene kuttes mindre (se `ui/channel_card.dart`). Testet med tester.
- 5.11.2026: 2.1.41: rekkefølgen på bibliotekene i Plex-fanen (se Plex under Arkitektur). Testet med tester og den
  falske Plex-serveren (`homeVideos` gir et tredje bibliotek). Eieren tok den i bruk samme dag (bilde: TV-serier over
  Filmer), men ville ikke ha pilene i sidemenyen hele tiden; 2.1.42 har dem bare i valget av biblioteker.
- 8.11.2026: 2.1.46: eieren 8.11 fikk ikke lagt inn et nytt IPTV-abonnement (Xtream Codes etter leverandørens
  guide), men kanalene kom til slutt (trolig bare treg første henting av en stor liste; feilmeldingen han så, er ikke
  kjent). Innloggingen sier nå hva som er galt, og prøver andre klient-ID-er når VLC avvises (se `xtream_source.dart`
  under Arkitektur). Testet med tester; ikke prøvd mot en server som faktisk stenger ute VLC. Samme kveld, med det nye
  abonnementet: TV-spilleren sto og spant på en kanal («HLS rett fra leverandøren», ikke noe bilde). TV-spilleren:
  kommer det ikke bilde fra den siste adressen på 30 s, spør `_noPicture` leverandøren (`explainFailure`) før
  beskjeden vises. Loggen (lest rett fra PC-en hans med mappetilgang til `%APPDATA%\Fyrlys\Fyrlys`, `logg.txt`) viste
  at strømserveren ikke svarte (ingen svar, eller «curl: error: Could not connect to server»), mens lista kom fra
  leverandøren som vanlig; ingen app virket hjemme, men det virket på mobilnett, så hjemme med AdGuard av, og med
  AdGuard på igjen (også dagen etter, da DNS-minnet i Windows var gått ut). Trolig midlertidig hos leverandøren (nytt
  abonnement), ikke AdGuard. Tilbudt, ikke laget: en beskjed når lista svarer, men strømserveren ikke gjør det. Å
  lese loggen: «playlist: Reading plaintext playlist» kommer ved hver åpning (media_kit åpner med `loadlist` fra en
  midlertidig fil) og er ufarlig; mpv-en (zhongfly) henter http med curl, så nettfeilene heter «curl: …».
- 8.11.2026: 2.1.45: eieren 8.11: multiview krasjet da han valgte kanal («Sikkert fordi det var for mange
  kanaler»); ingen feilrapport. Kanalvalget har mapper (se `ui/multiview_page.dart`), bildene hentes høyst åtte om
  gangen (`ImageStore`), og loggen ligger på disk, så slutten kommer med i rapporten etter et krasj. Årsaken til
  krasjet er ikke funnet: mulig mange samtidige bildenedlastinger ved rask rulling i «Alle kanaler», eller mpv med
  to bilder. Testet med tester.
- 6.11.2026: 2.1.44: logoen til filmen/serien på detaljsiden i Plex-fanen (se Plex under Arkitektur). Eieren likte
  detaljsiden (bilde 6.11). Testet med tester; om serveren hans har logoer i `Image`, og at PNG-ene vises gjennomsiktige,
  er ikke prøvd.
- 5.11.2026: 2.1.43: Plex Home, velg hvem som ser på (se Plex under Arkitektur). Testet med tester og den falske
  Plex-serveren (`home`: Kari og Ola med PIN 1234); ikke prøvd mot plex.tv: svaret fra `/home/users` og `switch`,
  PIN-feilen og om administrerte brukere får serveren i `resources`.
- Åpent (31.10): 2.1.23 er ikke bekreftet på PC-en hans (infoen skal vise «(deinterlacet)», og vanlige kanaler og
  arkivet skal virke som før). Arkivet bruker ca. 10 s på å starte; eieren sa «kjør på» om å gjøre det raskere, og
  vi venter på en måling av hvor lenge mpv bruker med ulike valg (HLS/TS, kortere `demuxer-lavf-analyzeduration`/
  `probesize`, `demuxer-lavf-probe-info=nostreams`). Når den kommer: velg det raskeste som neste versjon.
  Chromecast: venter på om TV-kanaler og filmer spiller med 2.1.32 fra telefonen og PC-en (ellers en ny feilrapport,
  kopiert).
- Ideer senere (lista fra 26.10, han valgte 1 og 12): søk i programmene, påminnelser, sortere favorittkanalene, skjule
  kategorier/kanaler, minispiller (alltid øverst), medietaster og Windows sin medieboks (SMTC), bildeformat og
  lydforsinkelse, sove-timer, bildeundertekster (DVB/PGS) med libass, sikkerhetskopi av favoritter og innstillinger,
  signering av exe-en.
