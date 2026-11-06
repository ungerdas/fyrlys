// En Plex-server og plex.tv uten nett, med oppdiktede filmer og serier. Alt som spørres om, huskes.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object data, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(data)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _container(Map<String, Object?> body) => {'MediaContainer': body};

Map<String, Object?> _media(int part, {int height = 1080, String video = 'h264', String audio = 'eac3', int channels = 6}) =>
    {
      'videoResolution': '$height',
      'height': height,
      'videoCodec': video,
      'audioCodec': audio,
      'audioChannels': channels,
      'container': 'mkv',
      'Part': [
        {'id': part, 'key': '/library/parts/$part/1700000000/file.mkv', 'container': 'mkv', 'size': 123456},
      ],
    };

class FakePlex {
  /// adressene serveren har (som plex.tv oppgir dem)
  static const local = 'https://10-0-0-5.abc123.plex.direct:32400';
  static const lanHttp = 'http://10.0.0.5:32400';
  static const remote = 'https://1-2-3-4.abc123.plex.direct:32400';
  static const relay = 'https://5-6-7-8.def456.plex.direct:8443';

  /// innloggingen kontoen får, og den serveren har
  static const accountToken = 'konto-nokkel';
  static const serverToken = 'server-nokkel';

  /// Ola i Plex Home (administrert bruker med PIN-koden [olaPin]): innloggingen og den på serveren
  static const olaToken = 'ola-nokkel';
  static const olaServerToken = 'ola-server-nokkel';
  static const olaPin = '1234';

  bool localWorks = true;
  bool lanHttpWorks = true;
  bool remoteWorks = true;

  /// PIN-en får svar fra og med denne sjekken
  int approveAt = 1;
  int pinChecks = 0;

  /// /hubs/continueWatching/items og /hubs/promoted finnes ikke (eldre server)
  bool oldServer = false;

  /// et tredje bibliotek med filmer (lagt til på serveren)
  bool homeVideos = false;

  /// kontoen har Plex Home med Ola (ellers er Kari alene)
  bool home = false;

  final requests = <http.Request>[];
  late final MockClient client = MockClient(_handle);

  /// spørringene til [path], i rekkefølge
  List<Map<String, String>> calls(String path) => [
        for (final r in requests)
          if (r.url.path == path) r.url.queryParameters,
      ];

  static Map<String, Object?> serverJson(
          {String id = 'srv1', String name = 'Hjemme', bool owned = true, String token = serverToken}) =>
      {
        'name': name,
        'product': 'Plex Media Server',
        'productVersion': '1.41.0',
        'provides': 'server',
        'clientIdentifier': id,
        'accessToken': token,
        'owned': owned,
        'lastSeenAt': '2026-11-01T10:00:00Z',
        'connections': [
          {'protocol': 'https', 'address': '10.0.0.5', 'port': 32400, 'uri': local, 'local': true, 'relay': false, 'IPv6': false},
          {'protocol': 'https', 'address': 'fe80::1', 'port': 32400, 'uri': 'https://[fe80::1]:32400', 'local': true, 'relay': false, 'IPv6': true},
          {'protocol': 'https', 'address': '1.2.3.4', 'port': 32400, 'uri': remote, 'local': false, 'relay': false, 'IPv6': false},
          {'protocol': 'https', 'address': '5.6.7.8', 'port': 8443, 'uri': relay, 'local': false, 'relay': true, 'IPv6': false},
        ],
      };

  /// det som lagres i appen når Fyrlys er koblet til (prefs-nøkkelen plex_plain)
  static String saved({String? base = local}) => jsonEncode({
        'token': accountToken,
        'user': 'kari',
        'server': {
          'id': 'srv1',
          'name': 'Hjemme',
          'token': serverToken,
          'owned': true,
          'version': '1.41.0',
          'connections': [
            {'uri': local, 'protocol': 'https', 'address': '10.0.0.5', 'port': 32400, 'local': true, 'relay': false},
            {'uri': remote, 'protocol': 'https', 'address': '1.2.3.4', 'port': 32400, 'local': false, 'relay': false},
          ],
        },
        if (base != null) 'base': base,
      });

  // ── innholdet ──

  static final Map<String, Object?> movie = {
    'ratingKey': '10',
    'key': '/library/metadata/10',
    'type': 'movie',
    'title': 'Fyrlyset',
    'year': 2024,
    'summary': 'En film om et fyr ved havet.',
    'tagline': 'Lyset blir aldri slukket.',
    'audienceRating': 7.5,
    'contentRating': '12',
    'duration': 6000000,
    'thumb': '/library/metadata/10/thumb/1',
    'art': '/library/metadata/10/art/1',
    'Image': [
      {'alt': 'Fyrlyset', 'type': 'coverPoster', 'url': '/library/metadata/10/thumb/1'},
      {'alt': 'Fyrlyset', 'type': 'clearLogo', 'url': '/library/metadata/10/clearLogo/1700000000'},
    ],
    'librarySectionID': 1,
    'Genre': [
      {'tag': 'Drama'},
    ],
    'Director': [
      {'tag': 'Ola Regissør'},
    ],
    'Role': [
      {'tag': 'Kari Nordmann', 'role': 'Fyrvokter'},
    ],
    'Media': [_media(100, height: 2160, video: 'hevc')],
  };

  static final Map<String, Object?> started = {
    'ratingKey': '11',
    'key': '/library/metadata/11',
    'type': 'movie',
    'title': 'Nordlys',
    'year': 2023,
    'summary': 'Lys over fjellet.',
    'duration': 5400000,
    'viewOffset': 600000,
    'thumb': '/library/metadata/11/thumb/1',
    'librarySectionID': 1,
    'Media': [_media(110)],
  };

  static Map<String, Object?> episode(String key, int season, int number, String title,
          {int viewOffset = 0, int viewCount = 0, int part = 0}) =>
      {
        'ratingKey': key,
        'key': '/library/metadata/$key',
        'type': 'episode',
        'title': title,
        'grandparentTitle': 'Kysten',
        'grandparentRatingKey': '20',
        'grandparentThumb': '/library/metadata/20/thumb/1',
        'parentRatingKey': season == 1 ? '21' : '22',
        'parentIndex': season,
        'index': number,
        'summary': 'Episode $number av sesong $season.',
        'duration': 2520000,
        'viewOffset': viewOffset,
        'viewCount': viewCount,
        'thumb': '/library/metadata/$key/thumb/1',
        'librarySectionID': 2,
        'Media': [_media(part == 0 ? int.parse(key) * 10 : part)],
      };

  static final List<Map<String, Object?>> season1 = [
    episode('31', 1, 1, 'Stormen', viewCount: 1),
    episode('32', 1, 2, 'Etter stormen', viewOffset: 300000),
  ];

  static final List<Map<String, Object?>> season2 = [
    episode('33', 2, 1, 'Våren'),
    episode('34', 2, 2, 'Sommeren'),
  ];

  static final Map<String, Object?> show = {
    'ratingKey': '20',
    'key': '/library/metadata/20/children',
    'type': 'show',
    'title': 'Kysten',
    'year': 2022,
    'summary': 'En serie om kysten.',
    'leafCount': 4,
    'viewedLeafCount': 1,
    'childCount': 2,
    'thumb': '/library/metadata/20/thumb/1',
    'art': '/library/metadata/20/art/1',
    'Image': [
      {'alt': 'Kysten', 'type': 'clearLogo', 'url': '/library/metadata/20/clearLogo/1'},
      {'alt': 'Kysten', 'type': 'clearLogoWide', 'url': '/library/metadata/20/clearLogoWide/1'},
    ],
    'librarySectionID': 2,
  };

  static Map<String, Object?> season(String key, int index, int viewed) => {
        'ratingKey': key,
        'type': 'season',
        'title': 'Season $index',
        'index': index,
        'parentRatingKey': '20',
        'parentTitle': 'Kysten',
        'leafCount': 2,
        'viewedLeafCount': viewed,
        'thumb': '/library/metadata/$key/thumb/1',
      };

  Future<http.Response> _handle(http.Request r) async {
    requests.add(r);
    final u = r.url;
    if (u.host == 'plex.tv') return _plexTv(r);
    if (u.host == 'clients.plex.tv') return _clients(r);
    final origin = '${u.scheme}://${u.host}:${u.port}';
    final works = switch (origin) {
      local => localWorks,
      lanHttp => lanHttpWorks,
      remote => remoteWorks,
      _ => false,
    };
    if (!works) throw const SocketException('ingen kontakt');
    if (u.path == '/identity') return _json(_container({'machineIdentifier': 'srv1'}));
    final token = r.headers['X-Plex-Token'] ?? u.queryParameters['X-Plex-Token'];
    if (token != serverToken && token != olaServerToken) return _json({'error': 'nei'}, 401);
    return _server(r, ola: token == olaServerToken);
  }

  /// brukerne i Plex Home
  List<Map<String, Object?>> get homeUsers => [
        {
          'id': 1,
          'uuid': 'kari-uuid',
          'title': 'Kari',
          'username': 'kari',
          'thumb': 'https://plex.tv/users/kari-uuid/avatar?c=1',
          'admin': true,
          'restricted': false,
          'protected': false,
          'guest': false,
        },
        if (home)
          {
            'id': 2,
            'uuid': 'ola-uuid',
            'title': 'Ola',
            'username': '',
            'thumb': '',
            'admin': false,
            'restricted': true,
            'protected': true,
            'guest': false,
          },
      ];

  http.Response _clients(http.Request r) {
    final path = r.url.path;
    final token = r.headers['X-Plex-Token'];
    if (path == '/api/v2/resources') {
      // Ola ser bare serveren i hjemmet, med sin egen innlogging der
      if (token == olaToken) return _json([serverJson(owned: false, token: olaServerToken)]);
      if (token != accountToken) return _json({'error': 'nei'}, 401);
      return _json([
        serverJson(id: 'venn', name: 'Vennens server', owned: false),
        serverJson(),
        {'name': 'Telefonen', 'provides': 'client,player', 'clientIdentifier': 'tlf', 'accessToken': 'x'},
      ]);
    }
    if (token != accountToken) return _json({'error': 'nei'}, 401);
    if (r.method == 'GET' && path == '/api/v2/home/users') {
      return _json({'id': 9, 'name': 'Hjemmet', 'users': homeUsers});
    }
    if (r.method == 'POST' && path == '/api/v2/home/users/kari-uuid/switch') {
      return _json({'uuid': 'kari-uuid', 'title': 'Kari', 'authToken': accountToken});
    }
    if (r.method == 'POST' && path == '/api/v2/home/users/ola-uuid/switch' && home) {
      if (r.url.queryParameters['pin'] != olaPin) {
        return _json({
          'errors': [
            {'code': 1041, 'message': 'Invalid PIN', 'status': 403},
          ],
        }, 403);
      }
      return _json({'uuid': 'ola-uuid', 'title': 'Ola', 'authToken': olaToken});
    }
    return _json({'error': 'ukjent'}, 404);
  }

  http.Response _plexTv(http.Request r) {
    final path = r.url.path;
    if (r.method == 'POST' && path == '/api/v2/pins') {
      return _json({'id': 7, 'code': 'abcd1234', 'authToken': null, 'expiresAt': '2099-01-01T00:00:00Z'}, 201);
    }
    if (path == '/api/v2/pins/7') {
      pinChecks++;
      return _json({'id': 7, 'code': 'abcd1234', 'authToken': pinChecks >= approveAt ? accountToken : null});
    }
    if (path == '/api/v2/user') {
      if (r.headers['X-Plex-Token'] != accountToken) return _json({'error': 'nei'}, 401);
      return _json({'username': 'kari', 'title': 'Kari'});
    }
    return _json({'error': 'ukjent'}, 404);
  }

  /// [ola]: Ola i Plex Home spør (han har ikke sett noe ennå)
  http.Response _server(http.Request r, {bool ola = false}) {
    final u = r.url;
    final q = u.queryParameters;
    switch (u.path) {
      case '/library/sections':
        return _json(_container({
          'Directory': [
            {'key': '1', 'title': 'Mine filmer', 'type': 'movie'},
            {'key': '2', 'title': 'Mine serier', 'type': 'show'},
            {'key': '3', 'title': 'Musikk', 'type': 'artist'},
            if (homeVideos) {'key': '4', 'title': 'Hjemmevideoer', 'type': 'movie'},
          ],
        }));
      case '/library/sections/1/all':
        final all = [movie, started];
        final list = q['genre'] == '5' ? [movie] : all;
        final start = int.tryParse(q['X-Plex-Container-Start'] ?? '0') ?? 0;
        return _json(_container({'size': list.length - start, 'totalSize': list.length, 'Metadata': list.skip(start).toList()}));
      case '/library/sections/2/all':
        return _json(_container({'size': 1, 'totalSize': 1, 'Metadata': [show]}));
      case '/library/sections/1/genre':
        return _json(_container({
          'Directory': [
            {'key': '5', 'title': 'Drama'},
          ],
        }));
      case '/library/sections/2/genre':
        return _json(_container({'Directory': <Object>[]}));
      case '/hubs/continueWatching/items':
        if (oldServer) return _json({'error': 'ukjent'}, 404);
        if (ola) return _json(_container({'Metadata': <Object>[]}));
        return _json(_container({'Metadata': [started, season1[1]]}));
      case '/library/onDeck':
        return _json(_container({'Metadata': [season1[1]]}));
      case '/library/metadata/10':
        return _json(_container({'Metadata': [movie]}));
      case '/library/metadata/11':
        return _json(_container({'Metadata': [started]}));
      case '/library/metadata/20':
        return _json(_container({
          'Metadata': [
            {
              ...show,
              // som en ekte server: ett objekt, ikke en liste
              if (q['includeOnDeck'] == '1') 'OnDeck': {'Metadata': season1[1]},
            },
          ],
        }));
      case '/library/metadata/20/children':
        return _json(_container({'Metadata': [season('22', 2, 0), season('21', 1, 1)]}));
      case '/library/metadata/21/children':
        return _json(_container({'Metadata': season1}));
      case '/library/metadata/22/children':
        return _json(_container({'Metadata': season2}));
      case '/library/metadata/32':
        return _json(_container({
          'Metadata': [
            {
              ...season1[1],
              'Marker': [
                {'type': 'intro', 'startTimeOffset': 10000, 'endTimeOffset': 70000},
                {'type': 'credits', 'startTimeOffset': 1200000, 'endTimeOffset': 1230000, 'final': false},
                {'type': 'credits', 'startTimeOffset': 2460000, 'endTimeOffset': 2520000, 'final': true},
              ],
              'Media': [
                {
                  ..._media(320),
                  'Part': [
                    {
                      'id': 320,
                      'key': '/library/parts/320/1700000000/file.mkv',
                      'Stream': [
                        {'streamType': 1, 'codec': 'h264'},
                        {'streamType': 2, 'codec': 'eac3', 'channels': 6, 'languageCode': 'nor'},
                        {
                          'streamType': 3,
                          'codec': 'srt',
                          'key': '/library/streams/900',
                          'languageCode': 'nor',
                          'language': 'Norsk',
                          'displayTitle': 'Norsk (SRT External)',
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        }));
      case '/library/metadata/31' || '/library/metadata/33' || '/library/metadata/34':
        final key = u.pathSegments.last;
        final all = [...season1, ...season2];
        return _json(_container({
          'Metadata': [all.firstWhere((e) => e['ratingKey'] == key)],
        }));
      case '/hubs/promoted':
        if (oldServer) return _json({'error': 'ukjent'}, 404);
        // som en server som ikke ser på contentDirectoryID: det som ikke skal vises, tar appen bort selv
        return _json(_container({
          'Hub': [
            // har sin egen rad
            {
              'hubIdentifier': 'home.continue',
              'title': 'Fortsett å se',
              'type': 'mixed',
              'Metadata': [started],
            },
            // en samling som er lagt på Hjem, med episoder
            {
              'hubIdentifier': 'custom.collection.2.77',
              'title': 'Nytt fra Kystkanalen',
              'type': 'episode',
              'key': '/library/collections/77/children',
              'more': true,
              'Metadata': [season2[1], season2[0]],
            },
            {
              'hubIdentifier': 'movie.recentlyadded.1',
              'title': 'Nylig lagt til i Mine filmer',
              'type': 'movie',
              'librarySectionID': 1,
              'key': '/hubs/sections/1/recentlyAdded',
              'more': false,
              'Metadata': [movie, started],
            },
            {
              'hubIdentifier': 'tv.recentlyadded.2',
              'title': 'Nylig lagt til i Mine serier',
              'type': 'show',
              'librarySectionID': 2,
              'Metadata': [show],
            },
            // ikke film eller serie
            {
              'hubIdentifier': 'music.recent.3',
              'title': 'Nylig spilt',
              'type': 'track',
              'Metadata': [
                {'ratingKey': '900', 'type': 'track', 'title': 'En sang', 'librarySectionID': 3},
              ],
            },
          ],
        }));
      case '/library/collections/77/children':
        final all = [...season2, ...season1];
        final start = int.tryParse(q['X-Plex-Container-Start'] ?? '0') ?? 0;
        final size = int.tryParse(q['X-Plex-Container-Size'] ?? '100') ?? 100;
        return _json(_container({'totalSize': all.length, 'Metadata': all.skip(start).take(size).toList()}));
      case '/hubs/metadata/10/related':
        return _json(_container({
          'Hub': [
            {
              'title': 'Mer som dette',
              'Metadata': [started],
            },
          ],
        }));
      case '/hubs/search':
        final query = (q['query'] ?? '').toLowerCase();
        return _json(_container({
          'Hub': [
            {
              'type': 'movie',
              'Metadata': [
                for (final m in [movie, started])
                  if ('${m['title']}'.toLowerCase().contains(query)) m,
              ],
            },
            {
              'type': 'actor',
              'Metadata': [
                {'ratingKey': '500', 'type': 'actor', 'title': 'Kari Nordmann'},
              ],
            },
          ],
        }));
      case '/:/timeline' || '/:/scrobble' || '/:/unscrobble':
        return _json(_container({}));
    }
    return _json({'error': 'ukjent'}, 404);
  }
}
