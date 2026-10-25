# Fyrlys

TV fra IPTV-abonnementet ditt (Xtream Codes), med [mpv](https://mpv.io) som avspiller via
[media_kit](https://github.com/media-kit/media-kit). mpv spiller det meste: H.265, AC3, DTS, MKV,
flere lydspor og undertekster, med maskinvaredekoding.

Laget i Flutter, så samme kode gir Windows, Android og Android TV (og senere macOS, Linux og iOS).

## Last ned

Under **Releases** her på GitHub ligger:

- **Windows:** `Fyrlys-…-windows.zip`. Pakk ut og start `fyrlys.exe`. Windows kan advare fordi
  programmet ikke er signert: velg *Mer informasjon → Kjør likevel*.
- **Android og Android TV:** `Fyrlys-…-android-arm64-v8a.apk` passer de fleste nyere telefoner og
  TV-bokser; `armeabi-v7a` er for eldre og billigere bokser. Tillat installasjon fra ukjente kilder.

## Logg inn

- **Fyrlys-server:** adressen til Docker-versjonen av Fyrlys på serveren din, f.eks.
  `http://192.168.1.10:8766`. Da deler appen innloggingen hos leverandøren, favorittene og
  «Ta over» med nettsiden, og serveren holder styr på hvem som bruker tilkoblingene.
- **IPTV-leverandør:** server, brukernavn og passord fra leverandøren, eller hele M3U-lenken
  (`get.php?username=…&password=…`) i serverfeltet. Favorittene lagres da i appen.

## Bruk

- **TV:** kategorier (☆ legger dem øverst, pilene endrer rekkefølgen), søk, favoritter og «sist sett».
  Kanalkortene viser programmet som går nå.
- **Spilleren:** ↑/↓ (eller kanal +/− på fjernkontrollen) bytter kanal, mellomrom pauser, M slår av
  lyden, F gir fullskjerm på PC, Esc går tilbake. Lydspor og undertekster velges i spilleren.
  Brytes strømmen, prøver spilleren på nytt, inntil tre ganger i minuttet.

## Bygge selv

Byggene lages på GitHub Actions (`.github/workflows/build.yml`). Lokalt:

```bash
flutter create --org no.peag --project-name fyrlys --platforms=windows,android .
flutter run
```

`flutter create` lager det som mangler av plattformmappene, og skriver ikke over det som ligger i repoet.
