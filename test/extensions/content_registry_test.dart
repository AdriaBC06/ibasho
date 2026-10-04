// Ibasho — pruebas del Kōbō Content Registry.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/addon_manager.dart';
import 'package:ibasho/extensions/backdrop_pack.dart';
import 'package:ibasho/extensions/content_registry.dart';
import 'package:ibasho/extensions/install_policy.dart';
import 'package:ibasho/extensions/semver.dart';

const _png = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  6,
  0,
  0,
  0,
  31,
  21,
  196,
  137,
  0,
  0,
  0,
  13,
  73,
  68,
  65,
  84,
  8,
  215,
  99,
  248,
  207,
  192,
  240,
  31,
  0,
  5,
  0,
  1,
  255,
  137,
  153,
  61,
  29,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

// Cabecera WAV PCM mínima, suficiente para validar tipo en el registro.
const _wav = <int>[
  82,
  73,
  70,
  70,
  36,
  0,
  0,
  0,
  87,
  65,
  86,
  69,
  102,
  109,
  116,
  32,
  16,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  68,
  172,
  0,
  0,
  136,
  88,
  1,
  0,
  2,
  0,
  16,
  0,
  100,
  97,
  116,
  97,
  0,
  0,
  0,
  0,
];

Future<File> _bundle(Directory temp, String version) async {
  final manifest = <String, Object?>{
    'schema': 1,
    'id': 'com.justmre.registry-test',
    'name': 'Registry Test',
    'version': version,
    'publisher': 'Mr. E',
    'type': 'content-pack',
    'compatibility': <String, Object?>{
      'ibashoApi': '^1.0',
      'minIbasho': '0.9.0',
    },
    'entry': <String, Object?>{'content': 'content/bundle.json'},
    'permissions': <Object?>[],
    'assets': <String, Object?>{'icon': 'icon.png'},
    'metadata': <String, Object?>{'contentKind': 'kobo-bundle'},
  };
  final bundle = <String, Object?>{
    'kind': 'kobo-bundle',
    'format': 1,
    'backdrops': <Object?>[
      <String, Object?>{
        'id': 'night',
        'name': <String, Object?>{'es': 'Noche', 'en': 'Night'},
        'colors': <String, Object?>{
          'top': version == '1.0.0' ? '#102040' : '#301050',
          'base': '#203060',
          'deep': '#081020',
          'accent': '#66CCFF',
        },
        'dark': true,
        'motif': 'stars',
      },
    ],
    'music': <Object?>[
      <String, Object?>{
        'id': 'loop',
        'name': <String, Object?>{'es': 'Bucle', 'en': 'Loop'},
        'file': 'assets/loop.wav',
        'author': 'Mr. E',
        'license': 'CC0',
      },
    ],
    'cosmetics': <Object?>[
      <String, Object?>{
        'id': 'crown',
        'name': <String, Object?>{'es': 'Corona', 'en': 'Crown'},
        'file': 'assets/crown.png',
        'slot': 'head',
      },
    ],
    'stickers': <Object?>[
      <String, Object?>{
        'id': 'star',
        'name': <String, Object?>{'es': 'Estrella', 'en': 'Star'},
        'file': 'assets/star.png',
      },
    ],
    'games': <Object?>[
      <String, Object?>{
        'id': 'malla',
        'engine': 'malla',
        'name': <String, Object?>{'es': 'Malla', 'en': 'Malla'},
        'description': <String, Object?>{'es': 'Hexágonos', 'en': 'Hexagons'},
        'config': <String, Object?>{'maxPlayers': version == '1.0.0' ? 4 : 6},
      },
    ],
    'levels': <Object?>[
      <String, Object?>{
        'game': 'malla',
        'id': 'classic',
        'name': <String, Object?>{'es': 'Clásico', 'en': 'Classic'},
        'data': <String, Object?>{'size': 3, 'players': 2},
      },
    ],
    'localizations': <String, Object?>{
      'es': <String, Object?>{'malla.turn': 'Turno'},
      'en': <String, Object?>{'malla.turn': 'Turn'},
    },
  };
  final archive = Archive()
    ..add(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
    ..add(ArchiveFile.bytes('icon.png', _png))
    ..add(ArchiveFile.string('content/bundle.json', jsonEncode(bundle)))
    ..add(ArchiveFile.bytes('assets/loop.wav', _wav))
    ..add(ArchiveFile.bytes('assets/crown.png', _png))
    ..add(ArchiveFile.bytes('assets/star.png', _png));
  final file = File('${temp.path}/registry-$version.ibasho');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
  return file;
}

void main() {
  late Directory temp;
  late AddonManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kobo-registry-test-');
    manager = await AddonManager.open(
      root: Directory('${temp.path}/root'),
      host: const ExtensionHostProfile(ibashoVersion: SemVersion(0, 9, 0)),
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'carga todas las familias declarativas desde un único registro',
    () async {
      await manager.install(await _bundle(temp, '1.0.0'));
      final registry = await ExtensionContentLoader(manager).load();

      expect(registry.backdrops, hasLength(1));
      expect(registry.music, hasLength(1));
      expect(registry.cosmetics, hasLength(1));
      expect(registry.stickers, hasLength(1));
      expect(registry.games, hasLength(1));
      expect(registry.levels, hasLength(1));
      expect(
        registry.text(
          'com.justmre.registry-test',
          'malla.turn',
          'en',
          fallback: '?',
        ),
        'Turn',
      );
    },
  );

  test(
    'el gate conserva gacha nativo y admite solo fondos ext activos',
    () async {
      await manager.install(await _bundle(temp, '1.0.0'));
      final registry = await ExtensionContentLoader(manager).load();
      final external = registry.backdrops.single.preferenceId;

      expect(
        resolveBackdropAvailability(
          chosen: external,
          nativeOwned: false,
          extensionBackdrops: registry.backdrops,
        ),
        external,
      );
      expect(
        resolveBackdropAvailability(
          chosen: external,
          nativeOwned: false,
          extensionBackdrops: const <ExtensionBackdrop>[],
        ),
        '',
      );
      expect(
        resolveBackdropAvailability(
          chosen: 'sky',
          nativeOwned: true,
          extensionBackdrops: const <ExtensionBackdrop>[],
        ),
        'sky',
      );
      expect(
        resolveBackdropAvailability(
          chosen: 'sky',
          nativeOwned: false,
          extensionBackdrops: const <ExtensionBackdrop>[],
        ),
        '',
      );
    },
  );

  test('el registro sigue la versión activa después de rollback', () async {
    await manager.install(await _bundle(temp, '1.0.0'));
    await manager.install(await _bundle(temp, '1.1.0'));

    var registry = await ExtensionContentLoader(manager).load();
    expect(registry.games.single.config['maxPlayers'], 6);
    expect(registry.backdrops.single.extensionVersion, '1.1.0');
    expect(registry.music.single.extensionVersion, '1.1.0');
    expect(registry.cosmetics.single.extensionVersion, '1.1.0');
    expect(registry.stickers.single.extensionVersion, '1.1.0');

    await manager.activateVersion('com.justmre.registry-test', '1.0.0');
    registry = await ExtensionContentLoader(manager).load();
    expect(registry.games.single.config['maxPlayers'], 4);
    expect(registry.backdrops.single.extensionVersion, '1.0.0');
    expect(registry.music.single.extensionVersion, '1.0.0');
    expect(registry.cosmetics.single.extensionVersion, '1.0.0');
    expect(registry.stickers.single.extensionVersion, '1.0.0');
  });

  test('un paquete desactivado desaparece entero del registro', () async {
    await manager.install(await _bundle(temp, '1.0.0'));
    await manager.setEnabled('com.justmre.registry-test', false);
    final registry = await ExtensionContentLoader(manager).load();
    expect(registry.backdrops, isEmpty);
    expect(registry.music, isEmpty);
    expect(registry.cosmetics, isEmpty);
    expect(registry.stickers, isEmpty);
    expect(registry.games, isEmpty);
    expect(registry.levels, isEmpty);
  });
}
