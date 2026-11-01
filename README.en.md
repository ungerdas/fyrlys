<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">IPTV player for Windows and Android phones: live TV, TV guide, catch-up, movies and series.</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe"><b>Download for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android.apk"><b>Android</b></a>
  &nbsp;·&nbsp;
  <a href="README.md">Norsk</a>
</p>

Fyrlys plays your subscription from an IPTV provider, using an M3U link or Xtream Codes. It has no channels of its own.
The app is in English or Norwegian (it follows Windows or the phone; change it under the gear → Appearance).

## Features

- Live TV with favorites, categories, search and channel numbers
- TV guide, and catch-up (TV archive) when the provider has it
- Pause and rewind live TV
- NRK1, NRK2, NRK3 and NRK Super from NRK's own live streams, one channel each (the provider's stream is the fallback)
- Movies and series with “Continue watching” (Xtream Codes)
- Several logins, each with its own favorites, and multiview with a channel from each subscription
- mpv as the player: most formats, audio tracks and subtitles
- Mini player that stays on top (Windows), picture format and audio delay per channel
- Cast to a TV with Chromecast (the PC or the phone passes the stream on, so Fyrlys has to keep running while you cast)
- Updates itself

## Getting started

1. Download and run [`Fyrlys-oppsett.exe`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe)
   (Windows 10 and 11). If Windows warns you, choose *More info → Run anyway*.
2. Sign in with the M3U link or the Xtream Codes login from your provider. It is stored encrypted, only on your PC.
3. Settings are under the gear at the top.

Something not working? Save an error report (gear → Help) and [let us know](https://github.com/ungerdas/fyrlys/issues/new/choose).

If you would rather not install, use [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip) instead.

### Android

1. Download [`Fyrlys-android.apk`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android.apk) on
   the phone and open it. The first time, Android asks whether the browser (or file manager) may install apps: allow it.
   The app is not on Google Play.
2. Sign in as on the PC. The login is stored only in the app on the phone.
3. New versions: the app tells you, downloads when you tap *Download* and installs with *Install* (the first time you
   have to allow Fyrlys to install apps).

Phones with 64-bit Android 7 or newer (arm64). Turn the phone sideways to watch full screen. When you cast, the phone
passes the stream on to the TV: a notification shows that Fyrlys is running, also with the screen off. Closing the app
stops casting.

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
flutter create --org no.fyrlys --project-name fyrlys --platforms=windows,android .
flutter run
```

The player is [mpv](https://mpv.io) (libmpv, LGPL), from [mpv-winbuild](https://github.com/zhongfly/mpv-winbuild).
