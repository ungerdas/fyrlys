<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">IPTV player for Windows: live TV, TV guide, catch-up, movies and series.</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe"><b>Download for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="README.md">Norsk</a>
</p>

Fyrlys plays your subscription from an IPTV provider, using an M3U link or Xtream Codes. It has no channels of its own.
The app is in English or Norwegian (it follows Windows; change it under the gear → Appearance).

## Features

- Live TV with favorites, categories, search and channel numbers
- TV guide, and catch-up (TV archive) when the provider has it
- Pause and rewind live TV
- Movies and series with “Continue watching” (Xtream Codes)
- Several logins, each with its own favorites, and multiview with a channel from each subscription
- mpv as the player: most formats, audio tracks and subtitles
- Mini player that stays on top, picture format and audio delay per channel
- Cast to a TV with Chromecast (the PC has to stay on while you cast)
- Updates itself

## Getting started

1. Download and run [`Fyrlys-oppsett.exe`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe)
   (Windows 10 and 11). If Windows warns you, choose *More info → Run anyway*.
2. Sign in with the M3U link or the Xtream Codes login from your provider. It is stored encrypted, only on your PC.
3. Settings are under the gear at the top.

Something not working? Save an error report (gear → Help) and [let us know](https://github.com/ungerdas/fyrlys/issues/new/choose).

If you would rather not install, use [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip) instead.

<details>
<summary>Keys</summary>

| | |
| --- | --- |
| ↑ / ↓ | previous and next channel |
| 0–9 | channel number |
| ← / → | 10 seconds back and forward |
| Space | pause |
| F | full screen |
| I | mini player |
| Z | picture format |
| C | channel list |
| A | TV archive |
| V | multiview |
| Esc | back |

</details>

## Building

Made with Flutter, [media_kit](https://github.com/media-kit/media-kit) and [mpv](https://mpv.io). Builds are made by
[GitHub Actions](.github/workflows/build.yml).

```bash
flutter create --org no.fyrlys --project-name fyrlys --platforms=windows .
flutter run
```

The player is [mpv](https://mpv.io) (libmpv, LGPL), from [mpv-winbuild](https://github.com/zhongfly/mpv-winbuild).
