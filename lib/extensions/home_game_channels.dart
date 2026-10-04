// Ibasho — canales HOME para juegos declarados por Kōbō.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import '../ui/screens/channels/channel.dart';
import '../ui/widgets/glyphs.dart';
import 'content_models.dart';
import 'game_host_registry.dart';

/// ID estable del canal HOME de un juego Kōbō.
///
/// No contiene la versión de la extensión: así el orden elegido por el usuario
/// sobrevive a actualizaciones y rollbacks del mismo juego.
String koboHomeChannelId(ExtensionGame game) =>
    'kobo-game-${game.extensionId}-${game.id}';

/// Convierte los juegos del registro central en canales de primer nivel.
///
/// Solo aparecen juegos cuyo motor está compilado explícitamente en el host.
/// Un paquete declarativo puede solicitar `malla`, pero no introducir código
/// ejecutable ni registrar un motor nuevo.
List<ChannelSpec> koboGameChannelSpecs({
  required ExtensionContentRegistry registry,
  required String localeCode,
}) {
  final channels = <ChannelSpec>[];
  for (final game in registry.games) {
    if (!KoboGameHostRegistry.supports(game.engine)) continue;
    channels.add(
      ChannelSpec(
        id: koboHomeChannelId(game),
        glyph: game.engine == 'malla' ? Glyph.blocks : Glyph.play,
        label: (_) => game.label(localeCode),
        builder: (_) => KoboGameHostRegistry.build(
          game: game,
          levels: registry.levelsFor(game),
          localeCode: localeCode,
          text: (key, fallback) => registry.text(
            game.extensionId,
            key,
            localeCode,
            fallback: fallback,
          ),
        )!,
      ),
    );
  }
  return List<ChannelSpec>.unmodifiable(channels);
}
