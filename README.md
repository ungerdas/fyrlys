<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">IPTV-spiller for Windows: TV, TV-guide, TV-arkiv, filmer og serier.</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe"><b>Last ned for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="CHANGELOG.md">Hva er nytt</a>
  &nbsp;·&nbsp;
  <a href="README.en.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest"><img alt="Siste versjon" src="https://img.shields.io/github/v/release/ungerdas/fyrlys?label=versjon"></a>
</p>

Fyrlys spiller abonnementet ditt hos en IPTV-leverandør, med M3U-lenke eller Xtream Codes. Den har ingen kanaler selv.
Appen er på norsk eller engelsk (som Windows; byttes under tannhjulet → Utseende).

## Funksjoner

- TV med favoritter, kategorier, søk og kanalnummer
- TV-guide, og TV-arkiv når leverandøren har det
- Pause og spol tilbake i direktesendinger
- Filmer og serier med «Fortsett å se» (Xtream Codes)
- Flere innlogginger, hver med sine egne favoritter, og multiview med en kanal fra hvert abonnement
- mpv som avspiller: de fleste formater, lydspor og undertekster
- Minispiller som ligger øverst, bildeformat og lydforsinkelse per kanal
- Oppdaterer seg selv

## Kom i gang

1. Last ned og kjør [`Fyrlys-oppsett.exe`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe)
   (Windows 10 og 11). Advarer Windows, velg *Mer informasjon → Kjør likevel*.
2. Logg inn med M3U-lenken eller Xtream-innloggingen fra leverandøren. Den lagres kryptert, bare på PC-en.
3. Innstillingene ligger under tannhjulet øverst.

Noe som ikke virker? Lagre en feilrapport (tannhjulet → Hjelp) og [meld fra](https://github.com/ungerdas/fyrlys/issues/new/choose).

Vil du ikke installere, kan du bruke [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip) i stedet.

<details>
<summary>Taster</summary>

| | |
| --- | --- |
| ↑ / ↓ | forrige og neste kanal |
| 0–9 | kanalnummer |
| ← / → | 10 sekunder tilbake og fram |
| Mellomrom | pause |
| F | fullskjerm |
| I | minispiller |
| Z | bildeformat |
| C | kanallista |
| A | TV-arkivet |
| V | multiview |
| Esc | tilbake |

</details>

## Bygge selv

Laget i Flutter, med [media_kit](https://github.com/media-kit/media-kit) og [mpv](https://mpv.io). Byggene lages av
[GitHub Actions](.github/workflows/build.yml).

```bash
flutter create --org no.fyrlys --project-name fyrlys --platforms=windows .
flutter run
```

Avspilleren er [mpv](https://mpv.io) (libmpv, LGPL), fra [mpv-winbuild](https://github.com/zhongfly/mpv-winbuild).
