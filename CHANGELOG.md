# Endringer

Teksten under hver versjon brukes i releasen på GitHub (`.github/workflows/build.yml`).

## v2.0.0

Første ordentlige utgave av Fyrlys-appen, for Windows, Android og Android TV. Den kommer i tillegg til
nettsiden (Docker-versjonen), og kan logge inn mot Fyrlys-serveren eller rett mot IPTV-leverandøren.

**TV**
- Kanalkort med logo og programmet som går nå, kategorier (dine øverst), favoritter, sist sett og søk.
  Via Fyrlys-serveren deles favorittene med nettsiden.
- Spilleren er som på nettsiden: bildet med programinfo under og kanallista ved siden av, fullskjerm,
  volum, lydspor og undertekster. mpv spiller det meste (H.265, AC3, DTS, MKV) med maskinvaredekoding.
- Pause og spol tilbake i direktesendingen (via Fyrlys-serveren, de siste 30 minuttene): tidslinje,
  −10/+10 sekunder og «DIREKTE».
- Alle tilkoblinger i bruk: «Ta over». Brytes strømmen, prøver spilleren på nytt.
- Tastatur og fjernkontroll: ↑/↓ kanal, ←/→ spoling, mellomrom pause, F fullskjerm, C kanalliste, M lyd,
  Backspace forrige kanal.

**TV-guide**
- Seks timer fram, rød strek for nå, «Til nå», favoritter eller kategori, og søk.
- Doble og overlappende programmer fra leverandøren ryddes bort.

**Filmer og serier**
- Plakater med kategorier, sortering og søk, sider for filmer og serier (sesonger og episoder).
- Egen spiller med tidslinje, fortsett der du slapp, og neste episode av seg selv.
- «Fortsett å se» øverst.

**Oppdateringer**
- Fyrlys på Windows oppdaterer seg selv fra testbyggene (via Fyrlys-serveren) og legger dem inn når du lukker
  appen, eller straks med «Start på nytt nå».

**Filer**
- Windows: `Fyrlys-v2.0.0-windows.zip`. Pakk ut i en mappe du kan skrive til (f.eks. under Dokumenter) og
  start `fyrlys.exe`.
- Android og Android TV: `…-arm64-v8a.apk` for de fleste, `…-armeabi-v7a.apk` for eldre bokser.

**Kjent**
- Android oppdaterer seg ikke selv ennå.
- Apple (iPhone, iPad, Apple TV) støttes ikke av appen; nettsiden virker i Safari.
