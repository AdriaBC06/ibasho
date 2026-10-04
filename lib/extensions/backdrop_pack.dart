// Ibasho — compatibilidad Kōbō 0.3.x sobre el Content Registry 0.4.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/accent.dart';
import '../theme/menu_theme.dart';
import 'content_models.dart';
import 'content_registry.dart';

export 'content_models.dart' show ExtensionBackdrop, ExtensionBackdropMotif;

final extensionBackdropsProvider = FutureProvider<List<ExtensionBackdrop>>(
  (ref) async => (await ref.watch(extensionContentProvider.future)).backdrops,
);

ExtensionBackdrop? extensionBackdropByPreferenceId(
  Iterable<ExtensionBackdrop> backdrops,
  String id,
) {
  for (final backdrop in backdrops) {
    if (backdrop.preferenceId == id) return backdrop;
  }
  return null;
}

/// Mantiene la API pura usada por las pruebas de Kōbō 0.3.x.
List<ExtensionBackdrop> parseBackdropPackText(
  String text, {
  required String extensionId,
  required String extensionVersion,
}) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<dynamic, dynamic>) {
    throw const FormatException('el contenido debe ser un objeto JSON');
  }
  final root = Map<String, Object?>.from(decoded);
  if (root['kind'] != 'backdrop-pack') return const <ExtensionBackdrop>[];
  if (root['format'] != 1) {
    throw const FormatException('backdrop-pack.format debe ser 1');
  }
  final rawBackdrops = root['backdrops'];
  if (rawBackdrops is! List<Object?> ||
      rawBackdrops.isEmpty ||
      rawBackdrops.length > 32) {
    throw const FormatException('backdrops debe contener entre 1 y 32 fondos');
  }

  final seen = <String>{};
  final result = <ExtensionBackdrop>[];
  for (final raw in rawBackdrops) {
    if (raw is! Map<dynamic, dynamic>) {
      throw const FormatException('cada fondo debe ser un objeto');
    }
    final item = Map<String, Object?>.from(raw);
    final id = _id(item['id'], 'id');
    if (!seen.add(id)) throw FormatException('id de fondo duplicado: $id');
    final name = _name(item['name'], '$id.name');
    final colorsRaw = item['colors'];
    if (colorsRaw is! Map<dynamic, dynamic>) {
      throw FormatException('$id.colors debe ser un objeto');
    }
    final colors = Map<String, Object?>.from(colorsRaw);
    final dark = item['dark'];
    if (dark != null && dark is! bool) {
      throw FormatException('$id.dark debe ser booleano');
    }
    final motif = switch (item['motif']) {
      'stars' => ExtensionBackdropMotif.stars,
      'haze' => ExtensionBackdropMotif.haze,
      'aurora' => ExtensionBackdropMotif.aurora,
      _ => throw const FormatException('motif debe ser stars, haze o aurora'),
    };
    result.add(
      ExtensionBackdrop(
        extensionId: extensionId,
        extensionVersion: extensionVersion,
        id: id,
        name: name,
        top: _color(colors['top'], '$id.colors.top'),
        base: _color(colors['base'], '$id.colors.base'),
        deep: _color(colors['deep'], '$id.colors.deep'),
        accent: _color(colors['accent'], '$id.colors.accent'),
        dark: dark == true,
        motif: motif,
      ),
    );
  }
  return List<ExtensionBackdrop>.unmodifiable(result);
}

String resolveBackdropAvailability({
  required String chosen,
  required bool nativeOwned,
  required Iterable<ExtensionBackdrop> extensionBackdrops,
}) {
  if (chosen.isEmpty) return '';
  if (!chosen.startsWith('ext:')) return nativeOwned ? chosen : '';
  return extensionBackdropByPreferenceId(extensionBackdrops, chosen) == null
      ? ''
      : chosen;
}

MenuTheme? resolvedMenuTheme(
  String id,
  Iterable<ExtensionBackdrop> extensionBackdrops,
) {
  final external = extensionBackdropByPreferenceId(extensionBackdrops, id);
  if (external == null) return menuThemeFor(id);

  final ornament = switch (external.motif) {
    ExtensionBackdropMotif.stars => Ornament.stars,
    ExtensionBackdropMotif.haze => Ornament.sheen,
    ExtensionBackdropMotif.aurora => Ornament.aura,
  };
  final surfaces = external.dark
      ? Surfaces.dark(
          external.top,
          external.base,
          deep: external.deep,
          ornament: ornament,
          glow: external.accent,
          glowAlt: external.base,
          glass: .58,
        )
      : Surfaces.tinted(
          external.top,
          external.base,
          deep: external.deep,
          strength: 1.24,
          glazed: true,
          ornament: ornament,
          glow: external.accent,
          glowAlt: external.base,
          glass: .66,
        );
  return MenuTheme(
    surfaces: surfaces,
    accent: external.dark
        ? brightAccent(external.accent)
        : readableAccent(external.accent),
  );
}

final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9-]{0,47}$');
final RegExp _hex = RegExp(r'^#[0-9A-Fa-f]{6}$');

String _id(Object? raw, String subject) {
  if (raw is! String || !_idPattern.hasMatch(raw)) {
    throw FormatException('$subject no es válido');
  }
  return raw;
}

KoboLocalizedText _name(Object? raw, String subject) {
  if (raw is! Map<dynamic, dynamic>) {
    throw FormatException('$subject debe ser un objeto');
  }
  final map = Map<String, Object?>.from(raw);
  String one(String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty || value.length > 100) {
      throw FormatException('$subject.$key debe ser texto');
    }
    return value.trim();
  }

  return KoboLocalizedText(es: one('es'), en: one('en'));
}

Color _color(Object? raw, String subject) {
  if (raw is! String || !_hex.hasMatch(raw)) {
    throw FormatException('$subject debe ser #RRGGBB');
  }
  return Color(0xff000000 | int.parse(raw.substring(1), radix: 16));
}
