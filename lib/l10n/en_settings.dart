// Engelsk for settings (se en.dart).

const enSettings = <String, String>{
  // settings_page.dart: innloggingene
  'Logg ut av {name}?': 'Sign out of {name}?',
  'Innloggingen slettes fra Fyrlys på denne PC-en. Favorittene og det du har sett, kommer tilbake hvis du logger '
          'inn igjen.':
      'The login is removed from Fyrlys on this PC. Your favorites and what you have watched come back if you sign '
          'in again.',
  'Avbryt': 'Cancel',
  'Logg ut': 'Sign out',
  'aktiv til {date}': 'active until {date}',
  '1 tilkobling': '1 connection',
  '{n} tilkoblinger': '{n} connections',
  'Byttet til {name}': 'Switched to {name}',
  'Innstillinger': 'Settings',
  'Innlogging': 'Login',
  'i bruk': 'in use',
  '{kind} · trykk for å bytte': '{kind} · click to switch',
  'Legg til innlogging': 'Add login',
  'En annen leverandør eller et annet abonnement': 'Another provider or subscription',
  'Logg ut av {name}': 'Sign out of {name}',
  'Mer om {name}': 'More options for {name}',
  'Gi nytt navn': 'Rename',
  'Logg ut og fjern': 'Sign out and remove',
  'Navn': 'Name',
  'F.eks. Hjemme eller Sport': 'E.g. Home or Sports',
  'Lagre': 'Save',

  // settings_page.dart: utseende og avspilling
  'Utseende': 'Appearance',
  'Tema': 'Theme',
  'Som Windows': 'Same as Windows',
  'Mørkt': 'Dark',
  'Lyst': 'Light',
  'Språk': 'Language',
  'Avspilling': 'Playback',
  'Språk for lyd og undertekster': 'Audio and subtitle languages',
  'Som filmen eller kanalen har dem': 'As the movie or channel provides them',
  'Fjern striper (deinterlacing)': 'Remove interlace lines (deinterlacing)',
  'For TV-kanaler som sendes interlacet (1080i). Bør stå på.':
      'For TV channels broadcast interlaced (1080i). Best left on.',
  'Jevn bevegelse (prøve)': 'Smooth motion (experimental)',
  'Tilpasser bildet til skjermens frekvens, så sport og panorering hakker mindre. Virker ikke på alle PC-er.':
      "Matches the video to the display's refresh rate, so sports and panning stutter less. Doesn't work on all PCs.",

  // settings_page.dart: listene
  'Kanaler og TV-guide': 'Channels and TV guide',
  'Hent listene på nytt': 'Reload lists',
  'Henter …': 'Loading…',
  'Kanalene og kategoriene fra leverandøren (1 kanal)': 'Channels and categories from the provider (1 channel)',
  'Kanalene og kategoriene fra leverandøren ({n} kanaler)': 'Channels and categories from the provider ({n} channels)',
  'Listene er hentet på nytt (1 kanal).': 'The lists have been reloaded (1 channel).',
  'Listene er hentet på nytt ({n} kanaler).': 'The lists have been reloaded ({n} channels).',

  // settings_page.dart: hjelp
  'Hjelp': 'Help',
  'Lagre feilrapport': 'Save error report',
  'Versjonen, innstillingene og loggen, uten passord og leverandør. Legg den ved når du melder fra om en feil.':
      'The version, settings and log, without passwords or provider. Attach it when you report a problem.',
  'Feilrapporten er lagret: {name}': 'Error report saved: {name}',
  'Fikk ikke lagret feilrapporten ({error}).': "Couldn't save the error report ({error}).",
  'Meld fra om en feil': 'Report a problem',
  'På GitHub (krever en konto der)': 'On GitHub (requires an account there)',

  // settings_page.dart: oppdateringer
  'Oppdateringer': 'Updates',
  'Se etter oppdateringer': 'Check for updates',
  'Ser etter …': 'Checking…',
  'Ny versjon: {version}': 'New version: {version}',
  'ny versjon': 'the new version',
  'Laster ned {version} … {percent} %': 'Downloading {version}… {percent}%',
  'En ny versjon legges inn når du lukker Fyrlys': 'A new version will be installed when you close Fyrlys',
  '{version} legges inn når du lukker Fyrlys': '{version} will be installed when you close Fyrlys',
  '{version} er lastet ned og legges inn når du lukker Fyrlys.':
      '{version} has been downloaded and will be installed when you close Fyrlys.',
  'Oppdateringen feilet': 'The update failed',
  'Du har {version}. Fyrlys ser selv etter nye versjoner.':
      'You have {version}. Fyrlys checks for new versions automatically.',
  'Du har siste versjon ({version}).': 'You have the latest version ({version}).',
  'Fant {version}. Den lastes ned nå.': 'Found {version}. Downloading it now.',
  'Fikk ikke sjekket oppdateringer: {error}': "Couldn't check for updates: {error}",
  'Start på nytt nå': 'Restart now',

  // login_page.dart
  'Ny innlogging': 'New login',
  'Den lagres ved siden av den du har, og du bytter mellom dem i innstillingene.':
      "It's saved alongside the one you have, and you can switch between them in settings.",
  'M3U-lenke': 'M3U link',
  'Lenken til kanallista fra leverandøren. Er det en Xtream-lenke (get.php med brukernavn og passord), får du '
          'også filmer og serier.':
      'The channel list link from your provider. If it is an Xtream link (get.php with username and password), you '
          'also get movies and series.',
  'EPG-lenke (valgfri)': 'EPG link (optional)',
  'XMLTV, .xml eller .xml.gz': 'XMLTV, .xml or .xml.gz',
  'Står den tom, brukes EPG-lenken i lista': 'If left empty, the EPG link in the list is used',
  'Innloggingen du har fått fra IPTV-leverandøren (Xtream Codes).':
      'The login you got from your IPTV provider (Xtream Codes).',
  'Brukernavn': 'Username',
  'Passord': 'Password',
  'Kobler til …': 'Connecting…',
  'Logg inn': 'Sign in',
  'Kunne ikke koble til. Sjekk lenken eller adressen.': "Couldn't connect. Check the link or address.",

  // language_dialog.dart
  'Lydspor': 'Audio track',
  'Velg i den rekkefølgen du vil ha dem. Uten valg: det filmen eller kanalen selv har først.':
      'Pick them in the order you prefer. With none picked: whatever the movie or channel lists first.',
  'Undertekster': 'Subtitles',
  'Slås på når lyden er på et annet språk. Uten valg: bare når filmen selv slår dem på.':
      'Turned on when the audio is in another language. With none picked: only when the movie turns them on itself.',
  'Av': 'Off',
  'Bare ett': 'Only one',
  'Foretrukne språk …': 'Preferred languages…',
  'Bilde': 'Picture',
  'Bildeformat: {name} …': 'Picture format: {name}…',
  'Lydforsinkelse: {value} …': 'Audio delay: {value}…',
  'Lydspor og undertekster': 'Audio and subtitles',

  // languages.dart: språkene for lyd og undertekster
  'Norsk': 'Norwegian',
  'Engelsk': 'English',
  'Svensk': 'Swedish',
  'Dansk': 'Danish',
  'Finsk': 'Finnish',
  'Tysk': 'German',
  'Fransk': 'French',
  'Spansk': 'Spanish',
  '{first}, så {last}': '{first}, then {last}',
  'av': 'off',
  'Lyd: {languages}': 'Audio: {languages}',
  'Undertekster: {languages}': 'Subtitles: {languages}',

  // report.dart: feilrapporten
  'på': 'on',
  'Fyrlys – feilrapport': 'Fyrlys – error report',
  'Laget': 'Created',
  'Versjon': 'Version',
  'bygg': 'build',
  'Innlogginger': 'Logins',
  'Abonnement': 'Subscription',
  '{n} i bruk': '{n} in use',
  'fikk ikke svar': 'no response',
  'Kanaler': 'Channels',
  'kategorier': 'categories',
  'TV-arkiv': 'TV archive',
  'filmer og serier': 'movies and series',
  'Feil i listene': 'List errors',
  'Jevn bevegelse': 'Smooth motion',
  'Oppdatering': 'Update',
  'Logg': 'Log',
  'Oppdateringsloggen': 'Update log',
  'feilrapport': 'error-report',

  // failure.dart: når leverandøren avviser avspillingen
  'Kanalen finnes ikke hos leverandøren (HTTP 404). Hent listene på nytt i innstillingene, eller prøv en annen '
          'kanal.':
      "The provider doesn't have this channel (HTTP 404). Reload the lists in settings, or try another channel.",
  'Finnes ikke hos leverandøren (HTTP 404). Hent listene på nytt i innstillingene.':
      'Not found at the provider (HTTP 404). Reload the lists in settings.',
  'Leverandøren gir ikke tilgang (HTTP {code}). Sjekk at abonnementet er aktivt.':
      'The provider denies access (HTTP {code}). Check that your subscription is active.',
  'Feil hos leverandøren (HTTP {code}). Prøv igjen om litt.':
      'Error at the provider (HTTP {code}). Try again in a moment.',
  'Leverandøren avviser denne kanalen (HTTP {code}). Prøv en annen kanal, eller prøv igjen senere.':
      'The provider refuses this channel (HTTP {code}). Try another channel, or try again later.',
  'Leverandøren avviser avspillingen (HTTP {code}). Prøv igjen senere.':
      'The provider refuses playback (HTTP {code}). Try again later.',

  // updater.dart
  'Fyrlys er oppdatert til {version}.': 'Fyrlys has been updated to {version}.',
  'bygg {n}': 'build {n}',
  'GitHub svarte ikke': "GitHub didn't respond",
  'fikk ikke kontakt med GitHub': "couldn't reach GitHub",
  'GitHub viser ikke de nye versjonene (er repoet privat?)':
      "GitHub doesn't show the new versions (is the repository private?)",
  'GitHub svarte {code}': 'GitHub responded with {code}',
  'nedlastingen svarte {code}': 'the download responded with {code}',
  'nedlastingen ble ikke fullført': "the download didn't finish",
  'Oppdateringen ble ikke lastet ned: {error}': "The update wasn't downloaded: {error}",
  'Fyrlys kan ikke oppdatere seg selv i {folder}. Flytt mappen til et sted du eier, f.eks. Dokumenter.':
      "Fyrlys can't update itself in {folder}. Move the folder somewhere you own, e.g. Documents.",
  'Oppdateringen ble ikke lagt inn: {error}': "The update wasn't installed: {error}",

  // build_info.dart
  '(eget bygg)': '(own build)',
};
