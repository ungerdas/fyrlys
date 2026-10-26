# Fyrlys

TV, filmer og serier fra IPTV-abonnementet ditt (Xtream Codes), med [mpv](https://mpv.io) som avspiller via
[media_kit](https://github.com/media-kit/media-kit). mpv spiller det meste: H.265, AC3, DTS, MKV,
flere lydspor og undertekster, med maskinvaredekoding.

Laget i Flutter, så samme kode gir Windows, Android og Android TV (og senere macOS, Linux og iOS).

## Last ned

Under **Releases** her på GitHub ligger:

- **Windows:** `Fyrlys-…-windows.zip`. Pakk ut og start `fyrlys.exe`. Windows kan advare fordi
  programmet ikke er signert: velg *Mer informasjon → Kjør likevel*.
- **Android og Android TV:** `Fyrlys-…-android-arm64-v8a.apk` passer de fleste nyere telefoner og
  TV-bokser; `armeabi-v7a` er for eldre og billigere bokser. Tillat installasjon fra ukjente kilder.

**Testbygg:** releasen «Testbygg» har alltid siste bygg fra `main`, med de siste endringene. Versjon og
byggnummer står nederst i menyen i appen.

## Oppdateringer

Fyrlys på Windows oppdaterer seg selv fra testbyggene. Den ser etter nye bygg når den starter og hver 6. time,
laster dem ned i bakgrunnen og legger dem inn når du lukker appen, eller straks med «Start på nytt nå». Blir
den ikke lukket som vanlig, legges oppdateringen inn neste gang den starter. Menyen har også «Se etter
oppdateringer».

Er appen logget inn på en Fyrlys-server, hentes byggene derfra. Serveren trenger da en lesenøkkel til GitHub
(se README-en til Docker-versjonen). Uten Fyrlys-server spør appen GitHub direkte, som bare virker når repoet
er offentlig.

Fyrlys må ligge i en mappe du kan skrive til, f.eks. under Dokumenter (ikke Programfiler). Egne bygg (uten
byggnummer) oppdaterer seg ikke, og Android oppdaterer seg ikke selv ennå.

## Logg inn

- **Fyrlys-server:** adressen til Docker-versjonen av Fyrlys på serveren din, f.eks.
  `http://192.168.1.10:8766`. Da deler appen innloggingen hos leverandøren, favorittene og
  «Ta over» med nettsiden, og serveren holder styr på hvem som bruker tilkoblingene.
- **IPTV-leverandør:** server, brukernavn og passord fra leverandøren, eller hele M3U-lenken
  (`get.php?username=…&password=…`) i serverfeltet. Favorittene lagres da i appen.

## Bruk

- **Rask oppstart:** kanallista fra sist vises med en gang og oppdateres i bakgrunnen, og logoer og plakater
  lagres på disken.
- **Hjem:** startsiden når appen åpnes: kanalen du så sist (med programmet nå og etterpå, «Se videre»),
  favorittene med det som går nå og det som kommer etterpå, de andre kanalene du har sett, kategoriene dine, og
  nederst filmen eller serien du holder på med.
- **TV:** kategorier (☆ legger dem øverst, pilene endrer rekkefølgen), søk, favoritter og «sist sett».
  Kanalkortene viser programmet som går nå.
- **Kanalnummer:** tast nummeret (f.eks. 1 og 2 for kanal 12) på TV-siden, i TV-guiden eller i spilleren, så går
  den dit etter et lite øyeblikk (eller med en gang med OK/Enter).
- **TV-guide:** kanalene nedover og de neste seks timene bortover, med en rød strek for nå. Velg favorittene,
  alle kanaler eller en kategori, og søk i toppen. Trykk på det som går nå (eller kanalnavnet) for å se kanalen;
  trykk på noe som kommer senere for å lese om det. «Til nå» går tilbake til nå. På PC kan guiden dras med musa.
- **Spilleren** er som på nettsiden: bildet med kontroller, programinfo under og kanallista ved siden av
  (under på smale skjermer), med lista du kom fra, favorittene og søk. Fullskjerm (F, dobbeltklikk eller
  knappen) viser bare bildet, og kanallista kan da legges over det (C). En telefon på tvers viser bare bildet.
- **Pause og spol tilbake** i direktesendingen når appen er logget inn på en Fyrlys-server: serveren tar vare på
  de siste 30 minuttene. Tidslinja over knappene, −10/+10 sekunder (← og →), og «DIREKTE» (eller L) tar deg til
  direkte igjen. Hvor langt bak du er, står ved siden av.
- **Kanalbytte:** ↑/↓ (eller kanal +/− på fjernkontrollen) blar i kanalinfoen nederst i bildet (logo, nummer, nå og
  etterpå), og kanalen du stopper på, startes etter et øyeblikk (OK starter med en gang, Esc blir der du var).
- **Taster:** Backspace går til kanalen du så sist,
  mellomrom pauser, M slår av lyden, F fullskjerm, C kanallista, Esc går tilbake. På fjernkontrollen gir OK
  fullskjerm, og i fullskjerm kanallista; → går inn i kanallista og ← ut igjen.
- **Lyd:** glidebryter ved lydknappen og musehjulet over bildet (PC). Volumet huskes. Lydspor og undertekster
  velges i spilleren.
- **Språk:** «Språk for lyd og undertekster» i menyen (eller «Foretrukne språk …» i spillerens sporvalg): velg
  f.eks. norsk, så engelsk for lyden og norsk for undertekstene, så velger spilleren det selv. Undertekster slås
  bare på når lyden er på et annet språk, og kan også slås helt av. Via Fyrlys-serveren har TV-kanalene ett
  lydspor og ingen undertekster, så der gjelder valget filmer og serier.
- Under bildet står oppløsning, kodek, om bildet dekodes i maskinvare, lyden og hvor strømmen kommer fra.
- Brytes strømmen, prøver spilleren på nytt, inntil tre ganger i minuttet. Legges appen bort på telefon
  eller TV, gir den fra seg tilkoblingen og starter kanalen igjen når du kommer tilbake.
- **Filmer og Serier:** fanene øverst (nederst på telefon). Velg kategori og rekkefølge (leverandørens, nyeste
  først eller A–Å), eller søk; flere plakater hentes etter hvert som du blar. En film har «Spill av», eller
  «Fortsett fra …» og «Fra begynnelsen» når du har sett litt av den. En serie har «Spill av S01E01», eller
  «Fortsett S01E03» der du slapp (og den neste når en er sett ferdig), og sesongene og episodene, med en strek
  under det du har sett.
- **Fortsett å se** øverst under Filmer og Serier: filmer du ikke har sett ferdig, og serier med episoden du er
  på (eller den neste). Trykk for å fortsette med en gang; krysset tar den bort.
- **Filmspilleren:** tidslinje du kan dra i, ←/→ ti sekunder, ↑/↓ lyd, mellomrom pause, N/P neste og forrige
  episode, F fullskjerm og Esc tilbake. Den husker hvor du slapp, og går videre til neste episode når en er
  ferdig. Lydspor og undertekster velges i spilleren.
- Har abonnementet bare én tilkobling, deler filmer, serier og TV den: en film på én enhet og TV på en annen
  går ikke samtidig.

## Bygge selv

Byggene lages på GitHub Actions (`.github/workflows/build.yml`). Lokalt:

```bash
flutter create --org no.peag --project-name fyrlys --platforms=windows,android .
flutter run
```

`flutter create` lager det som mangler av plattformmappene, og skriver ikke over det som ligger i repoet.

### Fast signeringsnøkkel for Android

Uten egen nøkkel signeres hvert bygg med en ny, tilfeldig nøkkel, og Android nekter da å legge et nytt bygg oppå
det gamle (appen må avinstalleres først). Lag en nøkkel én gang, f.eks. på Linux:

```bash
keytool -genkeypair -v -keystore fyrlys.jks -storetype PKCS12 -alias fyrlys \
  -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=Fyrlys"
base64 -w0 fyrlys.jks > fyrlys.jks.b64
```

Legg inn tre hemmeligheter under *Settings → Secrets and variables → Actions* i repoet:
`ANDROID_KEYSTORE_B64` (innholdet i `fyrlys.jks.b64`), `ANDROID_KEYSTORE_PASSWORD` (passordet du valgte) og
`ANDROID_KEY_ALIAS` (`fyrlys`). Ta vare på `fyrlys.jks` og passordet: uten dem kan ikke nye bygg legges oppå de
gamle. Første bygg med nøkkelen må installeres etter at den gamle appen er avinstallert; etter det går det rett.
