// Ibasho — pruebas adversariales del verificador .ibasho.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/extensions.dart';

const _onePixelPng = <int>[
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

Map<String, Object?> _manifest({String version = '1.0.0'}) => <String, Object?>{
  'schema': 1,
  'id': 'com.justmre.demo',
  'name': 'Demo',
  'version': version,
  'publisher': 'Mr. E',
  'type': 'content-pack',
  'compatibility': <String, Object?>{'ibashoApi': '^1.0', 'minIbasho': '0.9.0'},
  'entry': <String, Object?>{'content': 'content/data.json'},
  'permissions': <Object?>[],
  'assets': <String, Object?>{'icon': 'icon.png'},
};

Future<File> _writePackage(
  Directory temp, {
  List<ArchiveFile> extra = const <ArchiveFile>[],
  Map<String, Object?>? manifest,
}) async {
  final archive = Archive()
    ..add(
      ArchiveFile.string('manifest.json', jsonEncode(manifest ?? _manifest())),
    )
    ..add(ArchiveFile.bytes('icon.png', _onePixelPng))
    ..add(ArchiveFile.string('content/data.json', '{"hello":"ibasho"}'));
  for (final file in extra) {
    archive.add(file);
  }
  final bytes = ZipEncoder().encodeBytes(archive);
  final file = File('${temp.path}/demo.ibasho');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Uint8List _markZipEntryAsUnixSymlink(List<int> input, String filename) {
  final bytes = Uint8List.fromList(input);
  final data = ByteData.sublistView(bytes);
  const centralDirectorySignature = 0x02014b50;

  var offset = 0;
  while (offset + 46 <= bytes.length) {
    if (data.getUint32(offset, Endian.little) != centralDirectorySignature) {
      offset++;
      continue;
    }

    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    final nameStart = offset + 46;
    final nameEnd = nameStart + nameLength;
    if (nameEnd > bytes.length) break;

    final name = utf8.decode(bytes.sublist(nameStart, nameEnd));
    if (name == filename) {
      final madeBy = data.getUint16(offset + 4, Endian.little);
      // ZIP creator OS 3 = Unix; conserva la versión ZIP en el byte bajo.
      data.setUint16(offset + 4, (3 << 8) | (madeBy & 0xff), Endian.little);
      // POSIX S_IFLNK (0xA000) + permisos 0777, almacenados en los 16 bits altos.
      data.setUint32(offset + 38, 0xa1ff << 16, Endian.little);
      return bytes;
    }

    offset = nameEnd + extraLength + commentLength;
  }

  throw StateError(
    'No se encontró $filename en el directorio central del ZIP.',
  );
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ibasho-extension-test-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('verifica un paquete válido', () async {
    final package = await _writePackage(temp);
    final verified = await const PackageVerifier().verify(package);
    expect(verified.manifest.id, 'com.justmre.demo');
    expect(verified.sha256, hasLength(64));
    expect(verified.files, contains('content/data.json'));
  });

  test('rechaza ZIP Slip', () async {
    final package = await _writePackage(
      temp,
      extra: <ArchiveFile>[ArchiveFile.string('../escape.txt', 'no')],
    );
    await expectLater(
      const PackageVerifier().verify(package),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.unsafePath,
        ),
      ),
    );
  });

  test('rechaza symlinks', () async {
    // `archive` no codifica symlinks de forma fiable: crea una entrada normal
    // y marca su cabecera central como symlink Unix, igual que haría un ZIP
    // construido fuera de Dart. Así el fixture prueba al decoder/verificador,
    // no al encoder de la dependencia.
    final package = await _writePackage(
      temp,
      extra: <ArchiveFile>[ArchiveFile.string('link', '../outside')],
    );
    final patched = _markZipEntryAsUnixSymlink(
      await package.readAsBytes(),
      'link',
    );
    await package.writeAsBytes(patched, flush: true);

    await expectLater(
      const PackageVerifier().verify(package),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.unsupportedEntry,
        ),
      ),
    );
  });

  test('rechaza código ejecutable aunque no sea entrypoint', () async {
    final package = await _writePackage(
      temp,
      extra: <ArchiveFile>[
        ArchiveFile.string('payload/evil.dart', 'void main() {}'),
      ],
    );
    await expectLater(
      const PackageVerifier().verify(package),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.unsupportedEntry,
        ),
      ),
    );
  });

  test('rechaza colisiones de nombre insensibles a mayúsculas', () async {
    final package = await _writePackage(
      temp,
      extra: <ArchiveFile>[ArchiveFile.bytes('ICON.PNG', _onePixelPng)],
    );
    await expectLater(
      const PackageVerifier().verify(package),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.duplicateEntry,
        ),
      ),
    );
  });

  test('rechaza más de 500 entradas', () async {
    final extra = <ArchiveFile>[
      for (var i = 0; i < 498; i++) ArchiveFile.string('content/f$i.txt', 'x'),
    ];
    // 3 entradas base + 498 = 501.
    final package = await _writePackage(temp, extra: extra);
    await expectLater(
      const PackageVerifier().verify(package),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.tooManyEntries,
        ),
      ),
    );
  });
}
