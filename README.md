<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">
  IPTV-spiller for Windows og Linux.<br>
  TV med TV-guide, filmer og serier fra en M3U-lenke eller Xtream Codes, spilt av med mpv.
</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip"><b>Last ned for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-linux-x64.tar.gz"><b>Last ned for Linux</b></a>
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
- **Oppdaterer seg selv** når det kommer en ny versjon.
- Mørkt og lyst tema, og fungerer med mus og tastatur.

## Kom i gang

### 1. Last ned

Lenkene gir alltid siste versjon ([alle filene](https://github.com/ungerdas/fyrlys/releases/latest)).

**Windows 10 og 11:** [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip).
Pakk ut i en mappe du kan skrive til (f.eks. Dokumenter) og start `fyrlys.exe`. Windows kan advare fordi
programmet ikke er signert: velg *Mer informasjon → Kjør likevel*.

**Linux (x64):** [`Fyrlys-linux-x64.tar.gz`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-linux-x64.tar.gz).
Fyrlys bruker avspilleren mpv fra systemet, så installer den først:

```bash
sudo dnf install mpv-libs        # Fedora
sudo apt install libmpv2         # Ubuntu 24.04 og nyere, Debian 12 og nyere
```

Pakk ut i hjemmemappen og start den:

```bash
tar -xzf Fyrlys-linux-x64.tar.gz -C ~
~/Fyrlys/fyrlys
```

`~/Fyrlys/lag-snarvei.sh` legger Fyrlys i programmenyen, med ikon.

### 2. Logg inn

- **M3U-lenke** – lenken til kanallista fra leverandøren. TV-guiden hentes fra EPG-lenken (XMLTV, også `.xml.gz`)
  som står i lista, eller en du limer inn selv. Er det en Xtream-lenke (`get.php?username=…&password=…`), logger
  Fyrlys deg inn med Xtream Codes i stedet, så du også får filmer og serier.
- **Xtream Codes** – server, brukernavn og passord fra leverandøren. Gir TV, TV-guide, filmer og serier.

Innloggingen og favorittene lagres bare på enheten.

## Taster

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

I filmspilleren: ←/→ ti sekunder, ↑/↓ lyd, mellomrom pause, N/P neste og forrige episode, F fullskjerm og Esc
tilbake.

## Oppdateringer

Fyrlys oppdaterer seg selv, på Windows og Linux. Den ser etter nye versjoner når den starter og hver 6. time,
laster dem ned i bakgrunnen og legger dem inn når du lukker appen, eller straks med «Start på nytt nå». Menyen har
også «Se etter oppdateringer». Mappen Fyrlys ligger i må være din (ikke Programfiler eller `/opt`).

## Bygge selv

Fyrlys er laget i [Flutter](https://flutter.dev), med [media_kit](https://github.com/media-kit/media-kit) og
[mpv](https://mpv.io) som avspiller. Byggene lages på GitHub Actions
([`.github/workflows/build.yml`](.github/workflows/build.yml)). Lokalt:

```bash
flutter create --org no.peag --project-name fyrlys --platforms=windows,linux .
flutter run
```

`flutter create` lager det som mangler av plattformmappene, og skriver ikke over det som ligger i repoet. På Linux
trengs også `libmpv-dev` (Ubuntu) eller `mpv-devel` (Fedora). Testene kjøres med `flutter test`.
