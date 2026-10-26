# Endringer

Teksten under hver versjon brukes i releasen på GitHub (`.github/workflows/build.yml`).

## v2.1.4

- **TV direkte:** via Fyrlys-serveren spiller appen nå leverandørens strøm uendret, i stedet for at serveren gjør den
  om med ffmpeg. Du får originallyden (også 5.1), alle lydspor og undertekster, og språkvalget gjelder TV også.
  Serveren sender bare strømmen videre (så passordet blir der), og holder fortsatt styr på tilkoblingen: «Ta over»
  virker som før, og serveren oppdaterer seg ikke mens du ser.
- **Pause og spoling i appen:** appen tar selv vare på det siste mens du ser (på disken, omtrent en halvtime på PC og
  noen minutter på telefon og TV). Tidslinja, ←/→, «DIREKTE» og L virker som før, også når appen er logget inn rett
  mot leverandøren. Bufferet begynner når du åpner kanalen.

## v2.1.3

Mer smooth:
- **Rask oppstart:** kanallista fra sist vises med en gang og oppdateres i bakgrunnen, og programinfoen for
  favorittene og kanalene du har sett, hentes straks, så Hjem er fylt ut når du ser den.
- **Bildene huskes:** logoer, plakater og bakgrunner lagres på disken og pakkes ut i størrelsen de vises i (mindre
  hakking, særlig på TV-bokser), og tones inn når de kommer.
- **Kanalinfo ved bytte**, som på en TV-boks: logo, nummer, navn og programmet nå og etterpå nederst i bildet, også
  mens kanalen laster.
- **Rask blaing:** ↑/↓ blar i kanalinfoen, og bare kanalen du stopper på, startes (OK starter med en gang, Esc blir
  der du var). Kanalene du blar forbi, tar ikke tilkoblingen.
- **Myke overganger:** spillerne tones inn og ut, fanene og listene glir over i hverandre, og programinfoen tones inn.
- **Tydeligere fokus:** kortet du står på med fjernkontrollen eller har musa over, løftes litt.

## v2.1.2

Herfra får hver oppdatering neste nummer (2.1.3, 2.1.4 …). Denne kom først som 2.0.3.

- Ny startside, **Hjem**: kanalen du så sist med programmet nå og etterpå («Se videre»), favorittene med det som
  går nå og det som kommer etterpå, de andre kanalene du har sett, kategoriene dine, og nederst filmen eller
  serien du holder på med. Sidemenyen har fått ikoner.
- **Kanalnummer:** tast nummeret på TV-siden, i TV-guiden eller i spilleren (1 og 2 er kanal 12), som på
  fjernkontrollen. OK/Enter går dit med en gang.
- **Språk for lyd og undertekster** i menyen og i spilleren: f.eks. norsk, så engelsk. Spilleren velger sporene selv,
  undertekster bare når lyden er på et annet språk (eller aldri). Sporvalget i spilleren viser hvilket spor som
  faktisk spilles.
- Seriesiden har «Spill av S01E01», eller «Fortsett S01E03» der du slapp, og viser sesongen du er på.

## v2.0.2

- Film- og seriesider med stort bakgrunnsbilde, plakat, merker for år, sjanger, spilletid, vurdering,
  aldersgrense, land og kvalitet (4K, HDR, H.265, 5.1 …), og «Mer fra <kategori>» under filmer.
- Titler uten merker: «[PRE] [2026]» blir et merke på plakaten og året under; episoder uten «Serie - S01E01 - ».
- Fyllord som «Not yet available» vises ikke som beskrivelse.
- Episodene har nummeret på bildet, også når de har eget bilde.
- Versjonen (ikke byggnummeret) står i menyen og i beskjedene om oppdateringer.

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

**Rettet før utgivelsen** (etter en gjennomgang av koden)
- Brukernavn og passord hos leverandøren vises aldri i feilmeldinger fra spilleren, og passord med
  spesialtegn virker i adressene.
- Programinfo hentes først for det som faktisk vises (rask rulling fyller ikke køen), og en feil prøves igjen.
- Filmer/Serier spør ikke serveren om og om igjen når en side feiler.
- Fjernkontroll: OK trykker «Ta over» og «Prøv igjen»; Tilbake virker etter at telefonen er snudd.
- Spoling: → når du alt ser direkte, laster ikke strømmen på nytt, og en ny start etter spoling begynner
  ved direkte.
- Oppdateringen på Windows legger seg ikke over en Fyrlys som kjører, og legger den forrige utgaven tilbake
  hvis kopieringen feiler.
- Logoer uten bilde tåler flagg og emoji foran kanalnavnet; IPv6-adresser virker ved innlogging.

**Filer**
- Windows: `Fyrlys-v2.0.0-windows.zip`. Pakk ut i en mappe du kan skrive til (f.eks. under Dokumenter) og
  start `fyrlys.exe`.
- Android og Android TV: `…-arm64-v8a.apk` for de fleste, `…-armeabi-v7a.apk` for eldre bokser.

**Kjent**
- Android oppdaterer seg ikke selv ennå.
- Apple (iPhone, iPad, Apple TV) støttes ikke av appen; nettsiden virker i Safari.
