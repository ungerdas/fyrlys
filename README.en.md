<p align="center">
  <img src="assets/fyrlys.png" width="96" height="96" alt="">
</p>

<h1 align="center">Fyrlys</h1>

<p align="center">IPTV player for Windows, Android phones and Samsung TVs: live TV, TV guide, catch-up, movies and series.</p>

<p align="center">
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-oppsett.exe"><b>Download for Windows</b></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android.apk"><b>Android</b></a>
  &nbsp;·&nbsp;
  <a href="#samsung-tv"><b>Samsung TV</b></a>
  &nbsp;·&nbsp;
  <a href="README.md">Norsk</a>
</p>

Fyrlys plays your subscription from an IPTV provider, using an M3U link or Xtream Codes. It has no channels of its own.
The app is in English or Norwegian (it follows Windows, the phone or the TV; change it under the gear → Appearance).

## Features

- Live TV with favorites, categories, search and channel numbers
- TV guide, and catch-up (TV archive) when the provider has it
- Pause and rewind live TV
- NRK1, NRK2, NRK3 and NRK Super from NRK's own live streams, one channel each (the provider's stream is the fallback)
- Movies and series with “Continue watching” (Xtream Codes)
- Plex: the movies and shows on your Plex server in a tab of their own, with “Continue watching”, watched/unwatched, skip intro and next episode (gear → Plex). With Plex Home you choose who's watching
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

Something not working? Open the error report (gear → Help → Error report), copy it and [let us know](https://github.com/ungerdas/fyrlys/issues/new/choose).

If you would rather not install, use [`Fyrlys-windows.zip`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-windows.zip) instead.

### Android

1. Download [`Fyrlys-android.apk`](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-android.apk) on
   the phone and open it. The first time, Android asks whether the browser (or file manager) may install apps: allow it.
   The app is not on Google Play.
2. Sign in as on the PC. The login is stored only in the app on the phone.
3. New versions: the app tells you, downloads when you tap *Download* and installs with *Install* (the first time you
   have to allow Fyrlys to install apps).

Android 7 or newer, on phones (ARM) and in emulators such as BlueStacks (pick a 64-bit instance there). Turn the phone sideways to watch full screen. When you cast, the phone
passes the stream on to the TV: a notification shows that Fyrlys is running, also with the screen off. Closing the app
stops casting.

### Samsung TV

Samsung TVs from 2021 and newer (Tizen 6.0 to 10.0). Fyrlys is not in Samsung's app store, so you install it from a PC
or phone, with the TV in developer mode:

1. Download the package for the year your TV is from (on the back of the TV, or under *Settings → Support → About This
   TV*): [2021](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-tizen-2021.tpk),
   [2022–2025](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-tizen-2022-2025.tpk) or
   [2026](https://github.com/ungerdas/fyrlys/releases/latest/download/Fyrlys-tizen-2026.tpk).
   The TV's player is built for one Tizen version at a time, so the package has to match; if it doesn't, Fyrlys tells
   you which one does when you start a channel.
2. Turn on developer mode: open *Apps* on the TV, press 1 2 3 4 5 on the remote (or on the on-screen number pad), turn on
   *Developer mode* and enter the IP address of the PC or phone you install from. Restart the TV (hold the power button
   until it turns off and on again).
3. Install the package with [Apps2Samsung](https://github.com/Apps2Samsung/Apps2Samsung) (free, for Windows, Mac, Linux,
   Android and iPhone; not part of Fyrlys): pick the TV, pick *your own `.tpk`* and press *Install*. The first time you
   sign in with a Samsung account, and it makes a certificate for your TV (TVs only accept apps signed for them).
4. Fyrlys is under *Apps*. Sign in as on the PC.

New versions: Fyrlys tells you on the TV, and you install the new package the same way (from the same PC or phone, so
your login and favorites stay).

On the TV, the TV's own player plays everything, so the TV decides which formats work. Pausing and rewinding live TV,
multiview, the mini player, audio delay and Chromecast are not available there. The remote: ↑/↓ change channel, OK
shows the channel list, Back goes back, green or Info goes to the buttons below the picture (audio, subtitles, picture
format), red is the TV archive, blue *Watch from start* and yellow the picture format.

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
| S | skip the intro or credits (Plex) |
| Esc | back |

</details>

## Building

Made with Flutter, [media_kit](https://github.com/media-kit/media-kit) and [mpv](https://mpv.io). Builds are made by
[GitHub Actions](.github/workflows/build.yml).

```bash
flutter create --org no.fyrlys --project-name fyrlys --platforms=windows,android .
flutter run
```

The Samsung TV packages are built with [flutter-tizen](https://github.com/flutter-tizen/flutter-tizen) and the TV's own
player ([video_player_avplay](https://pub.dev/packages/video_player_avplay)): `flutter-tizen build tpk --dart-define=FYRLYS_TIZEN=true`
(with the TV's `api-version` in `tizen/tizen-manifest.xml`, see the workflow).

The player is [mpv](https://mpv.io) (libmpv, LGPL), from [mpv-winbuild](https://github.com/zhongfly/mpv-winbuild).
