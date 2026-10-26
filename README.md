<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">
  IPTV-spiller for Windows, Android og Android TV.<br>
  TV med TV-guide, filmer og serier fra en M3U-lenke eller Xtream Codes, spilt av med mpv.
</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip"><b>Last ned for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android-arm64-v8a.apk"><b>Last ned for Android</b></a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Hva er nytt</a>
</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/actions/workflows/build.yml"><img alt="Bygg" src="https://github.com/ungerdas/fyrlys/actions/workflows/build.yml/badge.svg"></a>
</p>

> Fyrlys har ingen kanaler eller innhold selv. Du trenger ditt eget abonnement hos en IPTV-leverandør.

## Funksjoner

- **Hjem** – kanalen du så sist, favorittene dine med det som går nå og etterpå, og kategoriene dine.
- **TV** – kategorier, favoritter, «sist sett» og søk. Kanalkortene viser programmet som går nå.
- **TV-guide** – kanalene nedover og de neste seks timene bortover, med en strek for nå.
- **Spiller** – kanallista ved siden av bildet, programinfo under, fullskjerm og rask kanalbytting.
- **Pause og spol tilbake** i direktesendinger. Appen tar selv vare på det siste mens du ser.
- **Kanalnummer** – tast nummeret, så går den dit.
- **Språk** – velg språk for lyd og undertekster én gang, så velger spilleren riktig spor selv.
- **Filmer og serier** (Xtream Codes) – plakater, kategorier, «Fortsett å se» og neste episode av seg selv.
- **mpv** spiller det meste: H.265, AC3, DTS, MKV, flere lydspor og undertekster, med maskinvaredekoding.
- Mørkt og lyst tema, og fungerer med mus, tastatur, berøring og fjernkontroll.

## Kom i gang

### 1. Last ned

| Plattform | Fil |
| --- | --- |
| Windows 10 og 11 | [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip) – pakk ut i en mappe du kan skrive til (f.eks. Dokumenter) og start `fyrlys.exe` |
| Android og Android TV | [`…-arm64-v8a.apk`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android-arm64-v8a.apk) for de fleste telefoner og TV-bokser, [`…-armeabi-v7a.apk`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android-armeabi-v7a.apk) for eldre og billigere bokser |

Lenkene gir alltid siste versjon ([alle filene](https://github.com/ungerdas/fyrlys/releases/latest)).
Windows kan advare fordi programmet ikke er signert: velg *Mer informasjon → Kjør likevel*. På Android må
installasjon fra ukjente kilder være tillatt.

### 2. Logg inn

- **M3U-lenke** – lenken til kanallista fra leverandøren. TV-guiden hentes fra EPG-lenken (XMLTV, også `.xml.gz`)
  som står i lista, eller en du limer inn selv. Er det en Xtream-lenke (`get.php?username=…&password=…`), logger
  Fyrlys deg inn med Xtream Codes i stedet, så du også får filmer og serier.
- **Xtream Codes** – server, brukernavn og passord fra leverandøren. Gir TV, TV-guide, filmer og serier.

Innloggingen og favorittene lagres bare på enheten.

## Taster og fjernkontroll

| I TV-spilleren | |
| --- | --- |
| ↑ / ↓ | blar i kanalene (starter etter et øyeblikk, OK med en gang) |
| 0–9 | går til kanalnummeret |
| ← / → | 10 sekunder tilbake og fram |
| L eller End | tilbake til direkte |
| Mellomrom | pause |
| Backspace | kanalen du så sist |
| F | fullskjerm |
| C | kanallista over bildet |
| M | lyd av og på |
| Esc | tilbake |

På fjernkontrollen gir OK fullskjerm, og i fullskjerm kanallista. → går inn i kanallista og ← ut igjen.

I filmspilleren: ←/→ ti sekunder, ↑/↓ lyd, mellomrom pause, N/P neste og forrige episode, F fullskjerm og Esc
tilbake.

## Oppdateringer

Fyrlys på Windows oppdaterer seg selv. Den ser etter nye versjoner når den starter og hver 6. time, laster dem
ned i bakgrunnen og legger dem inn når du lukker appen, eller straks med «Start på nytt nå». Menyen har også
«Se etter oppdateringer». Android-appen oppdaterer seg ikke selv ennå: last ned den nye APK-en og installer den
oppå den gamle.

## Bygge selv

Fyrlys er laget i [Flutter](https://flutter.dev), med [media_kit](https://github.com/media-kit/media-kit) og
[mpv](https://mpv.io) som avspiller. Byggene lages på GitHub Actions
([`.github/workflows/build.yml`](.github/workflows/build.yml)). Lokalt:

```bash
flutter create --org no.peag --project-name fyrlys --platforms=windows,android .
flutter run
```

`flutter create` lager det som mangler av plattformmappene, og skriver ikke over det som ligger i repoet.
Testene kjøres med `flutter test`.

<details>
<summary>Fast signeringsnøkkel for Android</summary>

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

</details>
