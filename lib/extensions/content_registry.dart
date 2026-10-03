// Ibasho — registro central de contenido declarativo de Kōbō.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'addon_manager.dart';
import 'content_models.dart';
import 'image_probe.dart';
import 'manifest.dart';
import 'path_policy.dart';

const int _maxContentBytes = 256 * 1024;
const int _maxImageBytes = 4 * 1024 * 1024;
const int _maxAudioBytes = 20 * 1024 * 1024;
const int _maxImageDimension = 4096;

final RegExp _contentId = RegExp(r'^[a-z][a-z0-9-]{0,47}$');
final RegExp _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}$');
const Set<String> _imageExtensions = <String>{'.png', '.jpg', '.jpeg', '.webp'};
const Set<String> _audioExtensions = <String>{'.wav', '.mp3', '.ogg'};

final extensionContentProvider = FutureProvider<ExtensionContentRegistry>(
  (ref) async => ExtensionContentLoader(await AddonManager.open()).load(),
);

class ExtensionContentLoader {
  const ExtensionContentLoader(this.manager);

  final AddonManager manager;

  Future<ExtensionContentRegistry> load() async {
    final out = _RegistryBuilder();
    final installed = await manager.listInstalled();
    for (final extension in installed) {
      if (!extension.enabled ||
          extension.manifest.type != ExtensionType.contentPack) {
        continue;
      }
      final content = extension.manifest.entry.content;
      if (content == null) continue;
      final file = File(
        p.joinAll(<String>[
          extension.installDirectory.path,
          ...content.split('/'),
        ]),
      );
      try {
        final length = await file.length();
        if (length <= 0 || length > _maxContentBytes) {
          throw const FormatException('entry.content vacío o mayor de 256 KiB');
        }
        final decoded = jsonDecode(
          utf8.decode(await file.readAsBytes(), allowMalformed: false),
        );
        if (decoded is! Map<dynamic, dynamic>) {
          throw const FormatException('entry.content debe ser un objeto JSON');
        }
        final root = Map<String, Object?>.from(decoded);
        final kind = root['kind'];
        if (kind == 'backdrop-pack') {
          await _parseLegacyBackdropPack(extension, root, out);
        } else if (kind == 'kobo-bundle') {
          await _parseBundle(extension, root, out);
        }
        // Un tipo futuro se ignora deliberadamente: una build antigua no
        // debe intentar adivinar semántica nueva.
      } catch (error, stack) {
        debugPrint(
          'Kobo content ignorado ${extension.manifest.id}@'
          '${extension.manifest.version}: $error\n$stack',
        );
      }
    }
    return out.freeze();
  }

  Future<void> _parseLegacyBackdropPack(
    InstalledExtension extension,
    Map<String, Object?> root,
    _RegistryBuilder out,
  ) async {
    if (root['format'] != 1) {
      throw const FormatException('backdrop-pack.format debe ser 1');
    }
    final raw = root['backdrops'];
    if (raw is! List<Object?> || raw.isEmpty || raw.length > 32) {
      throw const FormatException(
        'backdrops debe contener entre 1 y 32 fondos',
      );
    }
    for (final item in raw) {
      out.addBackdrop(_parseBackdrop(extension, _map(item, 'backdrop')));
    }
  }

  Future<void> _parseBundle(
    InstalledExtension extension,
    Map<String, Object?> root,
    _RegistryBuilder out,
  ) async {
    if (root['format'] != 1) {
      throw const FormatException('kobo-bundle.format debe ser 1');
    }

    for (final raw in _list(root, 'backdrops', max: 32)) {
      out.addBackdrop(_parseBackdrop(extension, _map(raw, 'backdrop')));
    }
    for (final raw in _list(root, 'music', max: 32)) {
      out.addMusic(await _parseMusic(extension, _map(raw, 'music')));
    }
    for (final raw in _list(root, 'cosmetics', max: 64)) {
      out.addCosmetic(await _parseCosmetic(extension, _map(raw, 'cosmetic')));
    }
    for (final raw in _list(root, 'stickers', max: 128)) {
      out.addSticker(await _parseSticker(extension, _map(raw, 'sticker')));
    }
    for (final raw in _list(root, 'levels', max: 128)) {
      out.addLevel(_parseLevel(extension, _map(raw, 'level')));
    }
    for (final raw in _list(root, 'games', max: 16)) {
      out.addGame(_parseGame(extension, _map(raw, 'game')));
    }

    final l10nRaw = root['localizations'];
    if (l10nRaw != null) {
      final l10n = _map(l10nRaw, 'localizations');
      final parsed = <String, Map<String, String>>{};
      for (final locale in <String>['es', 'en']) {
        final valuesRaw = l10n[locale];
        if (valuesRaw == null) continue;
        final values = _map(valuesRaw, 'localizations.$locale');
        if (values.length > 256) {
          throw FormatException('localizations.$locale supera 256 claves');
        }
        parsed[locale] = <String, String>{
          for (final entry in values.entries)
            _l10nKey(entry.key): _boundedText(
              entry.value,
              'localizations.$locale.${entry.key}',
              max: 240,
            ),
        };
      }
      out.addLocalizations(extension.manifest.id, parsed);
    }
  }

  ExtensionBackdrop _parseBackdrop(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) {
    final id = _id(item['id'], 'backdrop.id');
    final colors = _map(item['colors'], '$id.colors');
    final motif = switch (item['motif']) {
      'stars' => ExtensionBackdropMotif.stars,
      'haze' => ExtensionBackdropMotif.haze,
      'aurora' => ExtensionBackdropMotif.aurora,
      _ => throw FormatException('$id.motif debe ser stars, haze o aurora'),
    };
    final dark = item['dark'];
    if (dark != null && dark is! bool) {
      throw FormatException('$id.dark debe ser booleano');
    }
    return ExtensionBackdrop(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      id: id,
      name: _name(item['name'], '$id.name'),
      top: _color(colors['top'], '$id.colors.top'),
      base: _color(colors['base'], '$id.colors.base'),
      deep: _color(colors['deep'], '$id.colors.deep'),
      accent: _color(colors['accent'], '$id.colors.accent'),
      dark: dark == true,
      motif: motif,
    );
  }

  Future<ExtensionMusicTrack> _parseMusic(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) async {
    final id = _id(item['id'], 'music.id');
    final file = await _assetFile(
      extension,
      _boundedText(item['file'], '$id.file', max: 256),
      extensions: _audioExtensions,
      maxBytes: _maxAudioBytes,
      raster: false,
    );
    return ExtensionMusicTrack(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      id: id,
      name: _name(item['name'], '$id.name'),
      filePath: file.path,
      author: _boundedText(
        item['author'] ?? extension.manifest.publisher,
        '$id.author',
        max: 100,
      ),
      license: _boundedText(
        item['license'] ?? 'unspecified',
        '$id.license',
        max: 80,
      ),
    );
  }

  Future<ExtensionCosmetic> _parseCosmetic(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) async {
    final id = _id(item['id'], 'cosmetic.id');
    final file = await _assetFile(
      extension,
      _boundedText(item['file'], '$id.file', max: 256),
      extensions: _imageExtensions,
      maxBytes: _maxImageBytes,
      raster: true,
    );
    final slot = switch (item['slot']) {
      'head' => ExtensionCosmeticSlot.head,
      'face' => ExtensionCosmeticSlot.face,
      'neck' => ExtensionCosmeticSlot.neck,
      'body' => ExtensionCosmeticSlot.body,
      'hands' => ExtensionCosmeticSlot.hands,
      'feet' => ExtensionCosmeticSlot.feet,
      'back' => ExtensionCosmeticSlot.back,
      _ => throw FormatException('$id.slot no es válido'),
    };
    final anchor = item['anchor'] == null
        ? const <String, Object?>{}
        : _map(item['anchor'], '$id.anchor');
    return ExtensionCosmetic(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      id: id,
      name: _name(item['name'], '$id.name'),
      filePath: file.path,
      slot: slot,
      anchorX: _unit(anchor['x'] ?? .5, '$id.anchor.x'),
      anchorY: _unit(anchor['y'] ?? .22, '$id.anchor.y'),
      widthFraction: _range(item['width'] ?? .46, '$id.width', .08, 1.5),
    );
  }

  Future<ExtensionSticker> _parseSticker(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) async {
    final id = _id(item['id'], 'sticker.id');
    final file = await _assetFile(
      extension,
      _boundedText(item['file'], '$id.file', max: 256),
      extensions: _imageExtensions,
      maxBytes: _maxImageBytes,
      raster: true,
    );
    return ExtensionSticker(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      id: id,
      name: _name(item['name'], '$id.name'),
      filePath: file.path,
    );
  }

  ExtensionLevel _parseLevel(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) {
    final game = _id(item['game'], 'level.game');
    final id = _id(item['id'], 'level.id');
    final data = item['data'] == null
        ? const <String, Object?>{}
        : Map<String, Object?>.unmodifiable(
            _map(item['data'], '$game.$id.data'),
          );
    return ExtensionLevel(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      gameId: game,
      id: id,
      name: _name(item['name'], '$game.$id.name'),
      data: data,
    );
  }

  ExtensionGame _parseGame(
    InstalledExtension extension,
    Map<String, Object?> item,
  ) {
    final id = _id(item['id'], 'game.id');
    final engine = _id(item['engine'], '$id.engine');
    final config = item['config'] == null
        ? const <String, Object?>{}
        : Map<String, Object?>.unmodifiable(_map(item['config'], '$id.config'));
    return ExtensionGame(
      extensionId: extension.manifest.id,
      extensionVersion: extension.manifest.version.toString(),
      id: id,
      engine: engine,
      name: _name(item['name'], '$id.name'),
      description: _name(item['description'], '$id.description'),
      config: config,
    );
  }

  Future<File> _assetFile(
    InstalledExtension extension,
    String rawPath, {
    required Set<String> extensions,
    required int maxBytes,
    required bool raster,
  }) async {
    final safe = validatePackagePath(
      rawPath,
      subject: rawPath,
      allowTrailingSlash: false,
    );
    final ext = p.extension(safe).toLowerCase();
    if (!extensions.contains(ext)) {
      throw FormatException('formato no permitido para $safe');
    }
    // El backend de audio de Windows usa Media Foundation y el propio
    // Ibasho evita OGG allí. Kōbō hace lo mismo: el paquete debe aportar WAV
    // o MP3 si quiere reproducirse en Windows.
    if (!raster && Platform.isWindows && ext == '.ogg') {
      throw FormatException(
        '$safe usa OGG, no soportado por el backend de audio de Windows',
      );
    }
    final file = File(
      p.joinAll(<String>[extension.installDirectory.path, ...safe.split('/')]),
    );
    if (!await file.exists()) throw FormatException('falta el asset $safe');
    final length = await file.length();
    if (length <= 0 || length > maxBytes) {
      throw FormatException('$safe tiene un tamaño no permitido');
    }
    final bytes = await file.readAsBytes();
    if (raster) {
      final dimensions = probeRasterDimensions(bytes, safe);
      if (dimensions.width > _maxImageDimension ||
          dimensions.height > _maxImageDimension) {
        throw FormatException('$safe supera $_maxImageDimension px');
      }
    } else {
      _validateAudioHeader(bytes, ext, safe);
    }
    return file;
  }
}

class _RegistryBuilder {
  final List<ExtensionBackdrop> _backdrops = <ExtensionBackdrop>[];
  final List<ExtensionMusicTrack> _music = <ExtensionMusicTrack>[];
  final List<ExtensionCosmetic> _cosmetics = <ExtensionCosmetic>[];
  final List<ExtensionSticker> _stickers = <ExtensionSticker>[];
  final List<ExtensionLevel> _levels = <ExtensionLevel>[];
  final List<ExtensionGame> _games = <ExtensionGame>[];
  final Map<String, Map<String, Map<String, String>>> _localizations =
      <String, Map<String, Map<String, String>>>{};
  final Set<String> _keys = <String>{};

  void addBackdrop(ExtensionBackdrop value) {
    _unique('backdrop:${value.extensionId}:${value.id}');
    _backdrops.add(value);
  }

  void addMusic(ExtensionMusicTrack value) {
    _unique('music:${value.extensionId}:${value.id}');
    _music.add(value);
  }

  void addCosmetic(ExtensionCosmetic value) {
    _unique('cosmetic:${value.extensionId}:${value.id}');
    _cosmetics.add(value);
  }

  void addSticker(ExtensionSticker value) {
    _unique('sticker:${value.extensionId}:${value.id}');
    _stickers.add(value);
  }

  void addLevel(ExtensionLevel value) {
    _unique('level:${value.extensionId}:${value.gameId}:${value.id}');
    _levels.add(value);
  }

  void addGame(ExtensionGame value) {
    _unique('game:${value.extensionId}:${value.id}');
    _games.add(value);
  }

  void addLocalizations(
    String extensionId,
    Map<String, Map<String, String>> value,
  ) {
    _localizations[extensionId] = value;
  }

  void _unique(String key) {
    if (!_keys.add(key)) throw FormatException('contenido duplicado: $key');
  }

  ExtensionContentRegistry freeze() {
    int byId(Object a, Object b) => a.toString().compareTo(b.toString());
    _backdrops.sort((a, b) => byId(a.preferenceId, b.preferenceId));
    _music.sort((a, b) => byId(a.preferenceId, b.preferenceId));
    _cosmetics.sort((a, b) => byId(a.contentId, b.contentId));
    _stickers.sort((a, b) => byId(a.contentId, b.contentId));
    _levels.sort((a, b) => byId(a.contentId, b.contentId));
    _games.sort((a, b) => byId(a.contentId, b.contentId));
    return ExtensionContentRegistry(
      backdrops: List<ExtensionBackdrop>.unmodifiable(_backdrops),
      music: List<ExtensionMusicTrack>.unmodifiable(_music),
      cosmetics: List<ExtensionCosmetic>.unmodifiable(_cosmetics),
      stickers: List<ExtensionSticker>.unmodifiable(_stickers),
      levels: List<ExtensionLevel>.unmodifiable(_levels),
      games: List<ExtensionGame>.unmodifiable(_games),
      localizations: Map<String, Map<String, Map<String, String>>>.unmodifiable(
        _localizations.map(
          (extensionId, locales) => MapEntry(
            extensionId,
            Map<String, Map<String, String>>.unmodifiable(
              locales.map(
                (locale, values) =>
                    MapEntry(locale, Map<String, String>.unmodifiable(values)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<Object?> _list(Map<String, Object?> root, String key, {required int max}) {
  final raw = root[key];
  if (raw == null) return const <Object?>[];
  if (raw is! List<Object?> || raw.length > max) {
    throw FormatException('$key debe ser una lista de hasta $max elementos');
  }
  return raw;
}

Map<String, Object?> _map(Object? raw, String subject) {
  if (raw is! Map<dynamic, dynamic>)
    throw FormatException('$subject debe ser un objeto');
  return Map<String, Object?>.from(raw);
}

String _id(Object? raw, String subject) {
  final value = _boundedText(raw, subject, max: 48);
  if (!_contentId.hasMatch(value))
    throw FormatException('$subject no es un id válido');
  return value;
}

KoboLocalizedText _name(Object? raw, String subject) {
  final map = _map(raw, subject);
  return KoboLocalizedText(
    es: _boundedText(map['es'], '$subject.es', max: 100),
    en: _boundedText(map['en'], '$subject.en', max: 100),
  );
}

String _boundedText(Object? raw, String subject, {required int max}) {
  if (raw is! String || raw.trim().isEmpty || raw.length > max) {
    throw FormatException('$subject debe ser texto de 1 a $max caracteres');
  }
  return raw.trim();
}

String _l10nKey(String raw) {
  if (!RegExp(r'^[a-zA-Z0-9_.-]{1,80}$').hasMatch(raw)) {
    throw FormatException('clave de localización inválida: $raw');
  }
  return raw;
}

Color _color(Object? raw, String subject) {
  if (raw is! String || !_hexColor.hasMatch(raw)) {
    throw FormatException('$subject debe ser #RRGGBB');
  }
  return Color(0xff000000 | int.parse(raw.substring(1), radix: 16));
}

double _unit(Object? raw, String subject) => _range(raw, subject, 0, 1);

double _range(Object? raw, String subject, double min, double max) {
  if (raw is! num) throw FormatException('$subject debe ser numérico');
  final value = raw.toDouble();
  if (!value.isFinite || value < min || value > max) {
    throw FormatException('$subject debe estar entre $min y $max');
  }
  return value;
}

void _validateAudioHeader(List<int> bytes, String extension, String subject) {
  bool asciiAt(int offset, String value) {
    if (offset < 0 || offset + value.length > bytes.length) return false;
    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  final valid = switch (extension) {
    '.wav' => bytes.length >= 12 && asciiAt(0, 'RIFF') && asciiAt(8, 'WAVE'),
    '.ogg' => bytes.length >= 4 && asciiAt(0, 'OggS'),
    '.mp3' =>
      bytes.length >= 3 &&
          (asciiAt(0, 'ID3') ||
              (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)),
    _ => false,
  };
  if (!valid) {
    throw FormatException('$subject no coincide con su formato de audio');
  }
}
