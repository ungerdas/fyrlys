import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

// Det appen tar vare på mellom gangene: kanallista fra sist og bildene (logoer, plakater, bakgrunner).

/// Et kort, stabilt navn for en tekst (to 32-biters FNV-1a), til filnavn.
String stableHash(String text) {
  var a = 0x811c9dc5;
  var b = 0x9747b28c;
  for (final x in utf8.encode(text)) {
    a = ((a ^ x) * 0x01000193) & 0xffffffff;
    b = ((b ^ x) * 0x5bd1e995) & 0xffffffff;
  }
  return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
}

/// Kategoriene og kanalene slik de var sist.
typedef SavedLists = ({List<Category> categories, List<Channel> channels});

/// Kanallista fra sist, per kilde: appen viser den med en gang og henter den nye i bakgrunnen.
abstract class ListCache {
  Future<SavedLists?> read(String key);

  Future<void> write(String key, List<Category> categories, List<Channel> channels);
}

/// I en mappe på disken, én fil per kilde.
class FileListCache implements ListCache {
  FileListCache(this.dir);

  final Directory dir;

  File _file(String key) => File('${dir.path}${Platform.pathSeparator}lister-${stableHash(key)}.json');

  @override
  Future<SavedLists?> read(String key) async {
    try {
      final j = jsonDecode(await _file(key).readAsString());
      if (j is! Map || j['key'] != key) return null;
      final cats = j['categories'];
      final chans = j['channels'];
      if (cats is! List || chans is! List) return null;
      return (
        categories: [for (final c in cats) if (c is Map) Category.fromJson(c.map((k, v) => MapEntry('$k', v)))],
        channels: [for (final c in chans) if (c is Map) Channel.fromJson(c.map((k, v) => MapEntry('$k', v)))],
      );
    } on Object {
      // ingen fil ennå, eller en ødelagt: hentes på nytt
      return null;
    }
  }

  @override
  Future<void> write(String key, List<Category> categories, List<Channel> channels) async {
    try {
      await dir.create(recursive: true);
      final f = _file(key);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({
        'key': key,
        'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'categories': [for (final c in categories) c.toJson()],
        'channels': [for (final c in channels) c.toJson()],
      }));
      await tmp.rename(f.path);
    } on Object {
      // neste gang hentes lista som før
    }
  }
}

/// I minnet (testene).
class MemoryListCache implements ListCache {
  final Map<String, SavedLists> lists = {};

  @override
  Future<SavedLists?> read(String key) async => lists[key];

  @override
  Future<void> write(String key, List<Category> categories, List<Channel> channels) async =>
      lists[key] = (categories: categories, channels: channels);
}

/// Bildene på disk: hentes én gang og leses derfra siden (fornyes etter [maxAge]). Feiler nettet, brukes det
/// gamle bildet; et bilde som ikke finnes, prøves ikke igjen på ti minutter.
class ImageStore {
  ImageStore(this.dir, {http.Client? client, this.maxAge = const Duration(days: 14), this.maxBytes = 300 << 20})
      : _client = client ?? http.Client();

  /// bufferet appen bruker (null: bildene hentes fra nettet hver gang, som i testene)
  static ImageStore? instance;

  final Directory dir;
  final http.Client _client;
  final Duration maxAge;

  /// så mye bufferet kan bruke før de eldste bildene slettes
  final int maxBytes;

  final Map<String, Future<Uint8List>> _pending = {};
  final Map<String, DateTime> _failed = {};

  File fileFor(String url) => File('${dir.path}${Platform.pathSeparator}${stableHash(url)}');

  /// Bildet som bytes: fra disken, eller fra nettet (og lagres). Samme bilde hentes bare én gang om gangen.
  Future<Uint8List> bytes(String url) {
    final pending = _pending[url];
    if (pending != null) return pending;
    final f = _bytes(url);
    _pending[url] = f;
    return f.whenComplete(() => _pending.remove(url));
  }

  Future<Uint8List> _bytes(String url) async {
    final f = fileFor(url);
    Uint8List? old;
    try {
      final stat = await f.stat();
      if (stat.type == FileSystemEntityType.file && stat.size > 0) {
        old = await f.readAsBytes();
        if (DateTime.now().difference(stat.modified) < maxAge) return old;
      }
    } on Object {
      // leses fra nettet
    }
    final failed = _failed[url];
    if (failed != null && DateTime.now().difference(failed) < const Duration(minutes: 10)) {
      if (old != null) return old;
      throw ImageStoreException('$url ble ikke funnet nylig');
    }
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || res.bodyBytes.isEmpty || type.startsWith('text/')) {
        throw ImageStoreException('HTTP ${res.statusCode} for bildet');
      }
      _failed.remove(url);
      await _save(f, res.bodyBytes);
      return res.bodyBytes;
    } on Object {
      _failed[url] = DateTime.now();
      if (_failed.length > 2000) _failed.remove(_failed.keys.first);
      // et gammelt bilde er bedre enn ingen
      if (old != null) return old;
      rethrow;
    }
  }

  Future<void> _save(File f, Uint8List data) async {
    try {
      await dir.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(f.path);
    } on Object {
      // hentes fra nettet neste gang også
    }
  }

  /// Holder bufferet under [maxBytes] ved å slette de bildene som ble hentet for lengst siden.
  Future<void> prune() async {
    try {
      if (!await dir.exists()) return;
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final stat = await e.stat();
        files.add((e, stat));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      files.sort((x, y) => x.$2.modified.compareTo(y.$2.modified));
      for (final (file, stat) in files) {
        if (total <= maxBytes * 0.8) break;
        try {
          await file.delete();
          total -= stat.size;
        } on Object {
          // i bruk: prøves neste gang
        }
      }
    } on Object {
      // bufferet ryddes neste gang appen starter
    }
  }
}

class ImageStoreException implements Exception {
  const ImageStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
