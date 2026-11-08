// Engelsk for core (se en.dart).

const enCore = <String, String>{
  // session.dart
  'M3U-liste': 'M3U list',
  'Fikk ikke åpnet innloggingen. Fjern den og logg inn på nytt.': "Couldn't open the login. Remove it and sign in "
      'again.',
  'Uventet svar fra serveren da lista ble hentet': 'Unexpected response from the server while loading the list',
  'Kanaler': 'Channels',
  'Ikke logget inn': 'Not signed in',

  // models.dart
  'Tilkoblingen i abonnementet er i bruk akkurat nå. Ser noen på en annen enhet? Prøv igjen om litt.':
      'The connection in your subscription is in use right now. Is someone watching on another device? Try again '
          'in a moment.',
  'Alle de {n} tilkoblingene i abonnementet er i bruk akkurat nå. Ser noen på en annen enhet? Prøv igjen '
          'om litt.':
      'All {n} connections in your subscription are in use right now. Is someone watching on another device? Try '
          'again in a moment.',

  // xtream_source.dart
  'Skriv inn serveradressen': 'Enter the server address',
  'Ugyldig serveradresse': 'Invalid server address',
  'Fant ikke serien': 'Series not found',
  'Skriv inn brukernavn og passord': 'Enter username and password',
  'Feil brukernavn eller passord, eller abonnementet er ikke aktivert ennå. Sjekk store og små bokstaver.':
      "Incorrect username or password, or the subscription isn't activated yet. Check upper and lower case.",
  '{user} på {host}': '{user} on {host}',
  'Serveren vil ha https på denne porten. Skriv https:// foran adressen.':
      'The server wants https on this port. Put https:// in front of the address.',
  'Adressen er bak en nettleserkontroll (Cloudflare) som stopper IPTV-apper. Spør leverandøren om en '
          'serveradresse for apper.':
      'The address is behind a browser check (Cloudflare) that stops IPTV apps. Ask the provider for a server '
          'address for apps.',
  'Serveren avviste innloggingen (HTTP {code}). Sjekk at abonnementet er aktivt.':
      'The server rejected the login (HTTP {code}). Check that the subscription is active.',
  'Fant ikke Xtream Codes på adressen (HTTP 404). Sjekk serveradressen.':
      "Couldn't find Xtream Codes at the address (HTTP 404). Check the server address.",
  'IPTV-serveren svarte HTTP {code}': 'The IPTV server responded with HTTP {code}',
  'Serveren svarte tomt. Sjekk brukernavn og passord, og at abonnementet er aktivert.':
      'The server sent an empty response. Check the username and password, and that the subscription is activated.',
  'Adressen svarte med en nettside, ikke som en IPTV-server. Bruk serveradressen for Xtream Codes fra '
          'leverandøren, ikke adressen til nettsiden deres.':
      "The address returned a web page, not an IPTV server. Use the Xtream Codes server address from the provider, "
          'not the address of their website.',
  'Serveren svarte ikke som en Xtream-server': "The server didn't respond like an Xtream server",
  'Kanalen har ikke TV-arkiv': "This channel doesn't have a TV archive",

  // net_problem.dart
  'Serveren svarer ikke. Sjekk adressen og porten, eller prøv igjen senere.':
      "The server isn't responding. Check the address and port, or try again later.",
  'Serveren svarer ikke på https på denne porten. Prøv adressen med http:// foran.':
      "The server doesn't answer https on this port. Try the address with http:// in front.",
  'Sertifikatet til serveren godtas ikke, så den sikre tilkoblingen (https) ble stoppet. Har du fått en '
          'adresse med http:// fra leverandøren, bruk den.':
      "The server's certificate isn't trusted, so the secure connection (https) was stopped. If the provider gave "
          'you an address with http://, use that.',
  'Den sikre tilkoblingen (https) til serveren feilet.': 'The secure connection (https) to the server failed.',
  'Fant ikke serveren. Sjekk at adressen er skrevet riktig.':
      "Couldn't find the server. Check that the address is spelled correctly.",
  'Serveren tar ikke imot tilkoblinger på porten i adressen. Sjekk porten (tallet etter kolon).':
      "The server doesn't accept connections on the port in the address. Check the port (the number after the colon).",
  'Får ikke kontakt med serveren. Sjekk nettforbindelsen.': "Can't reach the server. Check your network connection.",
  'Serveren brøt forbindelsen. Prøv igjen om litt.': 'The server closed the connection. Try again in a moment.',
  'Får ikke kontakt med IPTV-serveren': "Can't reach the IPTV server",

  // m3u_source.dart
  'Lim inn M3U-lenken': 'Paste the M3U link',
  'Ugyldig lenke': 'Invalid link',
  'M3U-liste fra {host}': 'M3U list from {host}',
  'Får ikke hentet TV-guiden': "Couldn't download the TV guide",
  'Serveren avviste M3U-lista (HTTP {code})': 'The server denied access to the M3U list (HTTP {code})',
  'Serveren avviste TV-guiden (HTTP {code})': 'The server denied access to the TV guide (HTTP {code})',
  'Serveren svarte HTTP {code} for M3U-lista': 'The server responded with HTTP {code} for the M3U list',
  'Serveren svarte HTTP {code} for TV-guiden': 'The server responded with HTTP {code} for the TV guide',
  'Lenken ga ikke en M3U-liste': "The link didn't return an M3U list",
  'Lista har bare filmer og serier, ingen TV-kanaler': 'The list only has movies and series, no TV channels',
  'Fant ingen kanaler i lista': 'No channels found in the list',
  'Uten kategori': 'Uncategorized',
  'Fant ikke kanalen i lista. Hent listene på nytt i innstillingene.': "Couldn't find the channel in the list. "
      'Reload the lists in settings.',
  'Denne lista har ikke TV-arkiv': "This list doesn't have a TV archive",
  'M3U-lister har ikke filmer i Fyrlys': "M3U lists don't have movies in Fyrlys",
  'M3U-lister har ikke serier i Fyrlys': "M3U lists don't have series in Fyrlys",

  // main.dart
  'Fyrlys kunne ikke starte': "Fyrlys couldn't start",
  'Send dette når du melder fra om feilen:': 'Include this when you report the error:',
};
