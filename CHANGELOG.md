# Endringer

## v2.1.20

- **Tydeligere feilmeldinger:** kan ikke en kanal (eller film) spilles, står det hvorfor når Fyrlys finner det ut:
  at alle tilkoblingene i abonnementet er i bruk, eller at leverandøren avviser den, med svaret (HTTP-koden) den ga.
- **Bildeformat:** original, fyll skjermen, strekk, 16:9 eller 4:3, i menyen for lydspor og undertekster, eller med Z.
  På TV huskes det for hver kanal.
- **Lydforsinkelse:** flytt lyden i forhold til bildet (opptil 2 sekunder hver vei) når de ikke går i takt. På TV
  huskes den for hver kanal.
- **Minispiller:** et lite vindu nederst til høyre som alltid ligger øverst, med bare bildet (I, eller knappen ved
  fullskjerm). Dra i bildet for å flytte det; Esc eller dobbeltklikk gir det store vinduet tilbake.
- **Feilrapport:** Innstillinger → Hjelp → «Lagre feilrapport» lagrer versjonen, innstillingene og loggen i
  Nedlastinger, uten passord, brukernavn eller leverandøren, til å legge ved når du melder fra om en feil på GitHub.

## v2.1.19

- Filinfoen i programmet (Egenskaper → Detaljer) sier bare «Fyrlys». Innstillingene og innloggingen ligger der de lå.

## v2.1.18

- Rettet: «Kanalen kunne ikke spilles» når du gikk tilbake fra TV-arkivet, «Se fra start» eller multiview. Spilleren
  du gikk ut av, strømmet fortsatt et øyeblikk, så et abonnement med én tilkobling avviste kanalen. Nå stopper den
  med en gang.
- Avvises en kanal, prøver Fyrlys to ganger til før den gir opp. Er alle tilkoblingene i abonnementet i bruk (noen ser
  på en annen enhet), står det i feilmeldingen.

## v2.1.17

- **Multiview:** har du flere abonnementer (eller ett med flere tilkoblinger), kan du se flere kanaler samtidig: ett
  bilde per tilkobling, opptil fire. Hvert bilde får sin kanal fra sitt abonnement. Lyden kommer fra bildet du
  klikker på, og et dobbeltklikk (eller Enter) gjør det stort. Knappen «Multiview» står øverst på TV-siden og i
  spilleren (V), og kanalen du ser på, blir med.

## v2.1.16

- **Innstillinger:** menyen med tre prikker er byttet ut med et tannhjul øverst, som åpner en egen side med
  innloggingene (bytt, gi navn, legg til, logg ut), tema (som Windows, mørkt eller lyst), språk for lyd og
  undertekster, bildet (deinterlacing og jevn bevegelse), «Hent listene på nytt» og oppdateringer.
- Ved innloggingen du bruker, står det hva leverandøren sier om abonnementet (hvor lenge det varer og hvor mange
  tilkoblinger det har), når den sier det.

## v2.1.15

- Lukker du «Se fra start» i fullskjerm, er du fortsatt i fullskjerm i TV-spilleren (vinduet kunne gå ut av
  fullskjerm), og et maksimert vindu blir maksimert igjen etterpå.
- To innlogginger med samme navn (f.eks. to M3U-lister fra samme leverandør) viser ikke lenger hverandres kanalliste
  når Fyrlys starter.
- Taster du et kanalnummer rett før du åpner TV-arkivet, starter ikke kanalen mens arkivet spiller.
- Var du logget ut da du oppdaterte, får den første innloggingen favorittene du hadde fra før.

## v2.1.14

- **TV-arkiv** (Xtream Codes): har leverandøren arkiv for en kanal, kan du se det som har gått de siste dagene.
  Trykk på klokka ved kanalnavnet i TV-guiden, eller på «TV-arkiv» (A) i spilleren, og velg et program. Du kan spole,
  fortsette der du slapp, og spilleren går videre til neste program av seg selv.
- **Se fra start:** begynte programmet før du slo på, ser du det fra begynnelsen med én knapp i spilleren.
- **Flere innlogginger:** legg til en innlogging til (en annen leverandør eller et annet abonnement) og bytt mellom
  dem øverst i menyen. Du kan gi dem navn. Hver innlogging har sine egne favoritter, «sist sett» og «Fortsett å se»,
  og det du har fra før, følger med den du har nå.

## v2.1.13

- **Installasjonsprogram:** `Fyrlys-oppsett.exe` installerer Fyrlys for deg (uten administrator), med snarvei i
  startmenyen og på skrivebordet, og avinstallering under Apper. Fyrlys oppdaterer seg selv som før.
- **Innloggingen krypteres** med Windows sin egen beskyttelse, så bare din Windows-bruker kan lese passordet eller
  M3U-lenken. Det skjer av seg selv første gang den nye versjonen starter.
- **Vinduet husker** størrelsen og plassen sin, og om det var maksimert.
- **Bare én Fyrlys om gangen:** starter du den igjen, kommer vinduet som er åpent fram.
- Rydding: kode fra tiden med Fyrlys-serveren og testbyggene er fjernet, og byggeverktøyene er oppdatert.

## v2.1.12

- Fyrlys er nå bare for Windows. Android-versjonen er lagt ned, og det kommer ingen nye APK-er.

## v2.1.11

- «Oppdateringsserver» er borte fra menyen. Nye versjoner kommer alltid rett fra GitHub.

## v2.1.10

- Første vanlige release: hver versjon ligger nå under Releases på GitHub, og lenkene på forsiden gir alltid siste
  versjon. «Testbygg» er borte.

## v2.1.9

- Versjonen vises uten byggnummer og kode, i menyen og på GitHub. Teksten til hver versjon på GitHub er nå det som
  er nytt, i stedet for en liste over endringer i koden.
- Filene heter `Fyrlys-windows.zip` og `Fyrlys-android-….apk`.
- Hver versjon blir en vanlig release på GitHub (fra 2.1.10), og appen ser etter siste release.

## v2.1.8

- **Oppdateringene kommer rett fra GitHub.** Du trenger ingen oppdateringsserver lenger. Har du valgt en i menyen,
  brukes den fortsatt; tøm feltet for å hente rett fra GitHub.

## v2.1.7

- **«Du har siste versjon» når den ikke er det:** fant ikke appen testbyggene (privat repo uten
  oppdateringsserver, eller en nøkkel på serveren uten tilgang), sa den at du hadde siste versjon. Nå sier den
  hva som er galt.

## v2.1.6

- **Ny innlogging: M3U-lenke eller Xtream Codes.** Innloggingen mot Fyrlys-serveren er borte: appen henter TV rett
  fra leverandøren. Med en M3U-lenke får du kanalene og kategoriene fra lista, og TV-guide fra EPG-lenken (XMLTV) i
  lista eller en du limer inn selv. Er lenken en Xtream-lenke (get.php med brukernavn og passord), logges du inn med
  Xtream Codes i stedet, med TV-guide, filmer og serier.
- **Filmer og Serier** vises bare når kilden har dem (ikke for en vanlig M3U-liste).
- **Oppdateringsserveren:** Fyrlys-serveren brukes nå bare til å hente nye versjoner på Windows. Adressen står i menyen
  («Oppdateringsserver …») og tas med av seg selv fra innloggingen du hadde. Det samme gjør favorittene dine.
- Etter oppdateringen må du logge inn på nytt én gang, med M3U-lenken eller Xtream Codes.

## v2.1.5

- **Fjern striper (deinterlacing):** kanaler som sendes interlacet (1080i, vanlig hos NRK og TV 2), får ikke lenger
  «kammer» i bevegelse. Gjelder bare bilder som faktisk er interlacet, og er på som standard.
- **Jevn bevegelse (prøve):** tilpasser bildet til skjermens frekvens, så 25/50 fps hakker mindre på en 60 Hz-skjerm.
  Av som standard; slå den på i menyen for lydspor og undertekster. Infoen sier om den virker.
- **Mer info under bildet:** bilder i sekundet (og om bildet er deinterlacet), bitrate og tapte bilder, oppdatert
  hvert 5. sekund.

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
