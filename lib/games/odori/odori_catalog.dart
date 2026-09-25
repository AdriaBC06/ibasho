// Ibasho — Odori: las canciones y sus versiones (cantante e idioma), sacadas
// de los assets que trae la app.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Una version de una cancion: la instrumental o una voz en un idioma.
@immutable
class OdoriVersion {
  const OdoriVersion({required this.songId, required this.id, this.lang, this.singer});

  final String songId;

  /// Nombre del archivo sin extension: `yako`, `yako_ja_teto`...
  final String id;

  /// `ja`, `es` o `en`; `null` en la instrumental.
  final String? lang;

  /// Id del cantante (`teto`, `sinsy`...); `null` en la instrumental.
  final String? singer;

  bool get instrumental => singer == null;

  String get audioAsset => 'assets/odori/$songId/$id.ogg';
  String get scoreAsset => 'assets/odori/$songId/$id.json';

  /// Letra para el karaoke, si la hay en ese idioma.
  String? get lyricsAsset => lang == null ? null : 'assets/odori/$songId/${songId}_letra_$lang.json';

  /// Nombre del cantante para leer.
  String? get singerName => singer == null ? null : (singerNames[singer] ?? singer);

  static const Map<String, String> singerNames = {
    'teto': 'Kasane Teto',
    'sinsy': 'Sinsy',
    'sinsy_b': 'Sinsy',
    'kiritan': 'Tōhoku Kiritan',
    'zundamon': 'Zundamon',
    'merrow': 'Merrow',
  };
}

/// Una cancion con todas sus versiones.
@immutable
class OdoriSong {
  const OdoriSong({required this.id, required this.title, required this.native, required this.versions});

  final String id;

  /// Titulo en romaji, y en japones.
  final String title;
  final String native;
  final List<OdoriVersion> versions;

  /// «Ibasho feat. Kasane Teto», o solo «Ibasho» en la instrumental.
  String authorOf(OdoriVersion v) => v.singerName == null ? 'Ibasho' : 'Ibasho feat. ${v.singerName}';
}

/// Titulos de las canciones, por id de carpeta. Lo que no este aqui sale
/// con el id.
const Map<String, (String, String)> odoriTitles = {
  'tamagoyaki': ('Tamagoyaki', '卵焼き'),
  'hanabi': ('Hanabi no Ato', '花火のあと'),
  'nekobasu': ('Neko no Basu', 'ネコのバス'),
  'kasa': ('Ame no Hi no Kasa', '雨の日の傘'),
  'tsukimi': ('Tsukimi Dango', '月見だんご'),
  'kaerimichi': ('Kaeri Michi', '帰り道'),
  'ibasho': ('Ibasho', '居場所'),
  'yako': ('Yakō', '夜行列車'),
};

/// Orden del selector.
const List<String> odoriOrder = [
  'tamagoyaki',
  'hanabi',
  'nekobasu',
  'kasa',
  'tsukimi',
  'kaerimichi',
  'ibasho',
  'yako',
];

const Set<String> _langs = {'ja', 'es', 'en'};

/// Saca las canciones de una lista de rutas de assets.
@visibleForTesting
List<OdoriSong> songsFromAssets(Iterable<String> assets) {
  final found = <String, List<OdoriVersion>>{};
  final re = RegExp(r'^assets/odori/([a-z0-9_]+)/([a-z0-9_]+)\.ogg$');
  for (final a in assets) {
    final m = re.firstMatch(a);
    if (m == null) continue;
    final song = m.group(1)!;
    final file = m.group(2)!;
    final OdoriVersion v;
    if (file == song) {
      v = OdoriVersion(songId: song, id: file);
    } else if (file.startsWith('${song}_')) {
      final rest = file.substring(song.length + 1).split('_');
      if (rest.length == 2 && _langs.contains(rest[0])) {
        v = OdoriVersion(songId: song, id: file, lang: rest[0], singer: rest[1]);
      } else {
        continue;
      }
    } else {
      continue;
    }
    found.putIfAbsent(song, () => <OdoriVersion>[]).add(v);
  }
  int rank(String id) {
    final i = odoriOrder.indexOf(id);
    return i < 0 ? odoriOrder.length : i;
  }

  final ids = found.keys.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b));
  return [
    for (final id in ids)
      OdoriSong(
        id: id,
        title: odoriTitles[id]?.$1 ?? id,
        native: odoriTitles[id]?.$2 ?? '',
        versions: found[id]!
          ..sort((a, b) {
            // Primero la instrumental, luego por idioma y cantante.
            if (a.instrumental != b.instrumental) return a.instrumental ? -1 : 1;
            final l = _langOrder(a.lang).compareTo(_langOrder(b.lang));
            return l != 0 ? l : a.id.compareTo(b.id);
          }),
      ),
  ];
}

int _langOrder(String? lang) => const ['ja', 'es', 'en'].indexOf(lang ?? 'ja');

List<OdoriSong>? _cache;

/// Las canciones que trae la app.
Future<List<OdoriSong>> loadOdoriSongs() async {
  final cached = _cache;
  if (cached != null) return cached;
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return _cache = songsFromAssets(manifest.listAssets());
}
