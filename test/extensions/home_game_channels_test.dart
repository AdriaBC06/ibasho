// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/content_models.dart';
import 'package:ibasho/extensions/home_game_channels.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';

void main() {
  ExtensionGame game({
    required String version,
    String engine = 'malla',
    String id = 'malla',
  }) => ExtensionGame(
        extensionId: 'com.justmre.malla',
        extensionVersion: version,
        id: id,
        engine: engine,
        name: const KoboLocalizedText(es: 'Malla', en: 'Malla'),
        description: const KoboLocalizedText(es: 'Juego', en: 'Game'),
        config: const <String, Object?>{},
      );

  test('HOME id survives extension version rollback', () {
    expect(
      koboHomeChannelId(game(version: '2.0.1')),
      koboHomeChannelId(game(version: '1.1.0')),
    );
  });

  test('supported registry games become HOME channels', () {
    final malla = game(version: '2.0.1');
    final unknown = game(
      version: '1.0.0',
      engine: 'not-installed-engine',
      id: 'future-game',
    );
    final registry = ExtensionContentRegistry(
      games: <ExtensionGame>[malla, unknown],
    );

    final channels = koboGameChannelSpecs(
      registry: registry,
      localeCode: 'es',
    );

    expect(channels, hasLength(1));
    expect(channels.single.id, 'kobo-game-com.justmre.malla-malla');
    expect(channels.single.glyph, Glyph.blocks);
    expect(channels.single.gift, isFalse);
    expect(channels.single.gameId, isNull);
  });
}
