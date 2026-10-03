// Ibasho — modelos declarativos del Kōbō Content Registry.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show immutable;

@immutable
class KoboLocalizedText {
  const KoboLocalizedText({required this.es, required this.en});

  final String es;
  final String en;

  String resolve(String localeCode) => localeCode.startsWith('en') ? en : es;
}

enum ExtensionBackdropMotif { stars, haze, aurora }

@immutable
class ExtensionBackdrop {
  const ExtensionBackdrop({
    required this.extensionId,
    required this.extensionVersion,
    required this.id,
    required this.name,
    required this.top,
    required this.base,
    required this.deep,
    required this.accent,
    required this.dark,
    required this.motif,
  });

  final String extensionId;
  final String extensionVersion;
  final String id;
  final KoboLocalizedText name;
  final Color top;
  final Color base;
  final Color deep;
  final Color accent;
  final bool dark;
  final ExtensionBackdropMotif motif;

  // Se conserva el identificador de Kōbō 0.3.x para que una selección ya
  // guardada sobreviva a la migración al registro central.
  String get preferenceId => 'ext:$extensionId:$id';

  String label(String localeCode) => name.resolve(localeCode);
}

@immutable
class ExtensionMusicTrack {
  const ExtensionMusicTrack({
    required this.extensionId,
    required this.extensionVersion,
    required this.id,
    required this.name,
    required this.filePath,
    required this.author,
    required this.license,
  });

  final String extensionId;
  final String extensionVersion;
  final String id;
  final KoboLocalizedText name;
  final String filePath;
  final String author;
  final String license;

  String get preferenceId => 'ext:$extensionId:music:$id';
  String label(String localeCode) => name.resolve(localeCode);
}

enum ExtensionCosmeticSlot { head, face, neck, body, hands, feet, back }

@immutable
class ExtensionCosmetic {
  const ExtensionCosmetic({
    required this.extensionId,
    required this.extensionVersion,
    required this.id,
    required this.name,
    required this.filePath,
    required this.slot,
    required this.anchorX,
    required this.anchorY,
    required this.widthFraction,
  });

  final String extensionId;
  final String extensionVersion;
  final String id;
  final KoboLocalizedText name;
  final String filePath;
  final ExtensionCosmeticSlot slot;
  final double anchorX;
  final double anchorY;
  final double widthFraction;

  String get contentId => 'ext:$extensionId:cosmetic:$id';
  String label(String localeCode) => name.resolve(localeCode);
}

@immutable
class ExtensionSticker {
  const ExtensionSticker({
    required this.extensionId,
    required this.extensionVersion,
    required this.id,
    required this.name,
    required this.filePath,
  });

  final String extensionId;
  final String extensionVersion;
  final String id;
  final KoboLocalizedText name;
  final String filePath;

  String get contentId => 'ext:$extensionId:sticker:$id';
  String label(String localeCode) => name.resolve(localeCode);
}

@immutable
class ExtensionLevel {
  const ExtensionLevel({
    required this.extensionId,
    required this.extensionVersion,
    required this.gameId,
    required this.id,
    required this.name,
    required this.data,
  });

  final String extensionId;
  final String extensionVersion;
  final String gameId;
  final String id;
  final KoboLocalizedText name;
  final Map<String, Object?> data;

  String get contentId => 'ext:$extensionId:level:$gameId:$id';
  String label(String localeCode) => name.resolve(localeCode);
}

@immutable
class ExtensionGame {
  const ExtensionGame({
    required this.extensionId,
    required this.extensionVersion,
    required this.id,
    required this.engine,
    required this.name,
    required this.description,
    required this.config,
  });

  final String extensionId;
  final String extensionVersion;
  final String id;
  final String engine;
  final KoboLocalizedText name;
  final KoboLocalizedText description;
  final Map<String, Object?> config;

  String get contentId => 'ext:$extensionId:game:$id';
  String label(String localeCode) => name.resolve(localeCode);
  String describe(String localeCode) => description.resolve(localeCode);
}

@immutable
class ExtensionContentRegistry {
  const ExtensionContentRegistry({
    this.backdrops = const <ExtensionBackdrop>[],
    this.music = const <ExtensionMusicTrack>[],
    this.cosmetics = const <ExtensionCosmetic>[],
    this.stickers = const <ExtensionSticker>[],
    this.levels = const <ExtensionLevel>[],
    this.games = const <ExtensionGame>[],
    this.localizations = const <String, Map<String, Map<String, String>>>{},
  });

  final List<ExtensionBackdrop> backdrops;
  final List<ExtensionMusicTrack> music;
  final List<ExtensionCosmetic> cosmetics;
  final List<ExtensionSticker> stickers;
  final List<ExtensionLevel> levels;
  final List<ExtensionGame> games;

  /// extensionId -> locale -> key -> text.
  final Map<String, Map<String, Map<String, String>>> localizations;

  ExtensionBackdrop? backdropByPreferenceId(String id) {
    for (final value in backdrops) {
      if (value.preferenceId == id) return value;
    }
    return null;
  }

  ExtensionMusicTrack? musicByPreferenceId(String id) {
    for (final value in music) {
      if (value.preferenceId == id) return value;
    }
    return null;
  }

  ExtensionGame? gameByContentId(String id) {
    for (final value in games) {
      if (value.contentId == id) return value;
    }
    return null;
  }

  List<ExtensionLevel> levelsFor(ExtensionGame game) =>
      List<ExtensionLevel>.unmodifiable(
        levels.where(
          (level) =>
              level.extensionId == game.extensionId && level.gameId == game.id,
        ),
      );

  String text(
    String extensionId,
    String key,
    String localeCode, {
    required String fallback,
  }) {
    final byLocale = localizations[extensionId];
    if (byLocale == null) return fallback;
    final short = localeCode.startsWith('en') ? 'en' : 'es';
    return byLocale[short]?[key] ?? byLocale['es']?[key] ?? fallback;
  }
}
