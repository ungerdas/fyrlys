// Engelsk for player (se en.dart).

const enPlayer = <String, String>{
  // TV-spilleren: beskjeder og feil
  'Kanalen kunne ikke spilles ({message}).': "Couldn't play the channel ({message}).",
  'Kanalen stoppet (sendingen stoppet).': 'The channel stopped (the broadcast ended).',
  'Kanalen stoppet (bildet sto fast).': 'The channel stopped (the picture froze).',
  'Fikk ikke bilde fra kanalen.': 'No picture from the channel.',
  'Prøv igjen': 'Try again',
  'Direkte': 'Live',
  'DIREKTE': 'LIVE',
  '{time} bak direkte': '{time} behind live',
  'Gå til direkte (L)': 'Jump to live (L)',
  'Lyd av': 'Muted',
  'Lyd {n} %': 'Volume {n}%',
  'Volum {n} %': 'Volume {n}%',
  'Fant ikke kanal {n}': 'Channel {n} not found',
  'Bildeformat: {name}': 'Picture format: {name}',
  'Huskes for denne kanalen.': 'Remembered for this channel.',
  '{name} er lagt til i favoritter': '{name} added to favorites',
  '{name} er fjernet fra favoritter': '{name} removed from favorites',
  'Lagt til i favoritter': 'Added to favorites',
  'Fjernet fra favoritter': 'Removed from favorites',
  'Legg til i favoritter': 'Add to favorites',
  'Fjern fra favoritter': 'Remove from favorites',

  // programinfo og teknisk info
  'Deretter {time}: {title}': 'Next at {time}: {title}',
  'Så {time}  {title}': 'Next {time}  {title}',
  'HLS rett fra leverandøren': 'HLS directly from the provider',
  'MPEG-TS rett fra leverandøren': 'MPEG-TS directly from the provider',
  'rett fra leverandøren': 'directly from the provider',

  // kontrollene
  'Lukk (Esc)': 'Close (Esc)',
  'Pause (mellomrom)': 'Pause (space)',
  'Spill av (mellomrom)': 'Play (space)',
  '10 sekunder tilbake (←)': 'Back 10 seconds (←)',
  '10 sekunder fram (→)': 'Forward 10 seconds (→)',
  'Forrige kanal (↑)': 'Previous channel (↑)',
  'Neste kanal (↓)': 'Next channel (↓)',
  'Kanalen du så sist (Backspace)': 'Last channel watched (Backspace)',
  'Se fra start': 'Watch from start',
  'TV-arkiv (A)': 'TV archive (A)',
  'TV-arkiv': 'TV archive',
  'Multiview (V)': 'Multiview (V)',
  'Multiview': 'Multiview',
  'Lyd på (M)': 'Unmute (M)',
  'Lyd av (M)': 'Mute (M)',
  'Kanaler (C)': 'Channels (C)',
  'Minispiller (I)': 'Mini player (I)',
  'Fullskjerm (F)': 'Full screen (F)',
  'Avslutt fullskjerm (F)': 'Exit full screen (F)',

  // kanallista ved siden av
  'Kanaler': 'Channels',
  'Alle kanaler': 'All channels',
  'Lukk kanallista (Esc)': 'Close channel list (Esc)',
  '★ Favoritter': '★ Favorites',
  'Søk i lista': 'Search the list',
  'Tøm søket': 'Clear search',
  'Fant ingenting.': 'Nothing found.',
  'Ingen favoritter ennå. Trykk ☆ på en kanal for å legge den til.': 'No favorites yet. Click ☆ on a channel to add it.',
  'Ingen kanaler her.': 'No channels here.',

  // minispilleren
  'Stort vindu (I)': 'Exit mini player (I)',
  'Lukk': 'Close',

  // bildeformat og lydforsinkelse
  'Original': 'Original',
  'Fyll skjermen': 'Fill screen',
  'Strekk': 'Stretch',
  'Som kanalen sender det': 'As the channel sends it',
  'Uten svarte kanter; litt av bildet skjæres bort': 'No black bars; some of the picture is cropped',
  'Uten svarte kanter; bildet strekkes': 'No black bars; the picture is stretched',
  'For bilder som ser klemt ut': 'For pictures that look squeezed',
  'For bilder som ser strukket ut': 'For pictures that look stretched',
  'Bildeformat': 'Picture format',
  'Lydforsinkelse': 'Audio delay',
  'Lyden og bildet som de sendes': 'Audio and picture as broadcast',
  'Lyden kommer senere': 'Audio plays later',
  'Lyden kommer tidligere': 'Audio plays earlier',
  'Tidligere': 'Earlier',
  'Senere': 'Later',
  'Nullstill': 'Reset',
  'Ferdig': 'Done',

  // avspilleren: spor og infoen om strømmen
  'Spor {id}': 'Track {id}',
  'Av': 'Off',
  '{fps} fps (deinterlacet)': '{fps} fps (deinterlaced)',
  '{fps} fps (interlacet)': '{fps} fps (interlaced)',
  'programvaredekoding': 'software decoding',
  'maskinvaredekoding ({hwdec})': 'hardware decoding ({hwdec})',
  'jevn bevegelse': 'smooth motion',
  'jevn bevegelse virker ikke her': "smooth motion isn't working here",
  '1 tapt bilde': '1 dropped frame',
  '{n} tapte bilder': '{n} dropped frames',

  // Chromecast
  'Cast til TV': 'Cast to TV',
  'Cast til TV (Chromecast)': 'Cast to TV (Chromecast)',
  'Leter etter Chromecast …': 'Looking for Chromecasts…',
  'Fant ingen Chromecast. Den må være på samme nettverk som PC-en, og Windows-brannmuren må slippe '
          'Fyrlys gjennom på private nettverk.':
      'No Chromecast found. It must be on the same network as the PC, and Windows Firewall must let Fyrlys '
          'through on private networks.',
  'PC-en sender strømmen videre til TV-en, så den må stå på mens du caster.':
      'The PC passes the stream on to the TV, so it has to stay on while you cast.',
  'Let igjen': 'Search again',
  'Laster …': 'Loading…',
  'Pauset': 'Paused',
  'Pause': 'Pause',
  'Spilles på {name}': 'Playing on {name}',
  'Castes til {name}': 'Casting to {name}',
  'Stopp casting': 'Stop casting',
  'Volum på TV-en {n} %': 'TV volume {n}%',
  'Chromecasten kunne ikke spille dette.': "The Chromecast couldn't play this.",
  'Fikk ikke kontakt med {name}. Er den på og på samme nettverk som PC-en?':
      "Couldn't reach {name}. Is it on, and on the same network as the PC?",
  'Chromecasten fikk ikke hentet strømmen fra PC-en. Har Windows-brannmuren stoppet Fyrlys? '
          'Tillat Fyrlys på private nettverk, og prøv igjen.':
      "The Chromecast couldn't get the stream from the PC. Has Windows Firewall blocked Fyrlys? Allow Fyrlys on "
          'private networks and try again.',
  'Chromecasten kunne ikke spille dette. Den spiller HLS med H.264 og AAC; noen kanaler sendes på en måte '
          'den ikke støtter.':
      "The Chromecast couldn't play this. It plays HLS with H.264 and AAC; some channels are sent in a way it "
          "doesn't support.",
  'Mistet kontakten med {name}.': 'Lost the connection to {name}.',
  'Castingen til {name} ble stoppet.': 'Casting to {name} was stopped.',
  'Chromecasten stoppet avspillingen (feil i strømmen).': 'The Chromecast stopped playback (error in the stream).',
};
