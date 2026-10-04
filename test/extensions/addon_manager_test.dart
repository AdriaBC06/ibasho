// Ibasho — pruebas de instalación transaccional de extensiones.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/extensions.dart';

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

Future<File> _package(Directory temp, String version) async {
  final manifest = <String, Object?>{
    'schema': 1,
    'id': 'com.justmre.demo',
    'name': 'Demo',
    'version': version,
    'publisher': 'Mr. E',
    'type': 'content-pack',
    'compatibility': <String, Object?>{
      'ibashoApi': '^1.0',
      'minIbasho': '0.9.0',
    },
    'entry': <String, Object?>{'content': 'content/data.json'},
    'permissions': <Object?>[],
    'assets': <String, Object?>{'icon': 'icon.png'},
  };
  final archive = Archive()
    ..add(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
    ..add(ArchiveFile.bytes('icon.png', _png))
    ..add(ArchiveFile.string('content/data.json', '{"v":"$version"}'));
  final file = File('${temp.path}/demo-$version.ibasho');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive), flush: true);
  return file;
}

void main() {
  late Directory temp;
  late Directory root;
  late AddonManager manager;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ibasho-manager-test-');
    root = Directory('${temp.path}/root');
    manager = await AddonManager.open(
      root: root,
      host: const ExtensionHostProfile(ibashoVersion: SemVersion(0, 9, 0)),
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('instala, registra y deshabilita un content-pack', () async {
    final package = await _package(temp, '1.0.0');
    final installed = await manager.install(package);
    expect(installed.enabled, isTrue);
    expect(await installed.installDirectory.exists(), isTrue);

    await manager.setEnabled('com.justmre.demo', false);
    final listed = await manager.listInstalled();
    expect(listed, hasLength(1));
    expect(listed.single.enabled, isFalse);
  });

  test(
    'actualiza sin borrar la versión anterior y permite rollback explícito',
    () async {
      await manager.install(await _package(temp, '1.0.0'));
      await manager.install(await _package(temp, '1.1.0'));

      final oldDir = Directory('${root.path}/packages/com.justmre.demo/1.0.0');
      final newDir = Directory('${root.path}/packages/com.justmre.demo/1.1.0');
      expect(await oldDir.exists(), isTrue);
      expect(await newDir.exists(), isTrue);
      expect(
        (await manager.listInstalled()).single.manifest.version,
        const SemVersion(1, 1, 0),
      );

      var versions = await manager.listInstalledVersions('com.justmre.demo');
      expect(versions, hasLength(2));
      expect(versions.first.manifest.version, const SemVersion(1, 1, 0));
      expect(versions.first.active, isTrue);
      expect(versions.last.manifest.version, const SemVersion(1, 0, 0));
      expect(versions.last.active, isFalse);

      await manager.activateVersion('com.justmre.demo', '1.0.0');
      expect(
        (await manager.listInstalled()).single.manifest.version,
        const SemVersion(1, 0, 0),
      );
      versions = await manager.listInstalledVersions('com.justmre.demo');
      expect(versions.first.active, isFalse);
      expect(versions.last.active, isTrue);
    },
  );

  test('enumera versiones instaladas y marca una sola como activa', () async {
    await manager.install(await _package(temp, '1.0.0'));
    await manager.install(await _package(temp, '1.2.0'));

    final versions = await manager.listInstalledVersions('com.justmre.demo');
    expect(versions.map((v) => v.manifest.version).toList(), <SemVersion>[
      const SemVersion(1, 2, 0),
      const SemVersion(1, 0, 0),
    ]);
    expect(versions.where((v) => v.active), hasLength(1));
    expect(
      versions.singleWhere((v) => v.active).manifest.version,
      const SemVersion(1, 2, 0),
    );
  });

  test('bloquea downgrade automático', () async {
    await manager.install(await _package(temp, '1.1.0'));
    final downgrade = await _package(temp, '1.0.0');
    await expectLater(
      manager.install(downgrade),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.downgradeBlocked,
        ),
      ),
    );
  });

  test('un paquete inválido no rompe la versión activa', () async {
    await manager.install(await _package(temp, '1.0.0'));
    final bad = File('${temp.path}/bad.ibasho')..writeAsStringSync('not a zip');
    await expectLater(manager.install(bad), throwsA(isA<ExtensionException>()));
    final active = await manager.listInstalled();
    expect(active.single.manifest.version, const SemVersion(1, 0, 0));
  });

  test(
    'rechaza instalar dos veces la misma version con error de dominio',
    () async {
      final package = await _package(temp, '1.0.0');
      await manager.install(package);
      await expectLater(
        manager.install(package),
        throwsA(
          isA<ExtensionException>().having(
            (error) => error.code,
            'code',
            ExtensionErrorCode.alreadyInstalled,
          ),
        ),
      );
    },
  );

  test('desinstala el indice y todas las versiones del disco', () async {
    await manager.install(await _package(temp, '1.0.0'));
    await manager.install(await _package(temp, '1.1.0'));
    final base = Directory('${root.path}/packages/com.justmre.demo');
    expect(await base.exists(), isTrue);

    await manager.uninstall('com.justmre.demo');

    expect(await manager.listInstalled(), isEmpty);
    expect(await base.exists(), isFalse);
  });
}
