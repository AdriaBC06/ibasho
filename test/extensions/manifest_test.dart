// Ibasho — pruebas del manifiesto IES.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/extensions.dart';

void main() {
  const parser = ManifestParser();

  Map<String, Object?> validManifest({
    String type = 'content-pack',
    String version = '1.0.0',
  }) => <String, Object?>{
    'schema': 1,
    'id': 'com.justmre.demo',
    'name': 'Demo',
    'version': version,
    'publisher': 'Mr. E',
    'type': type,
    'compatibility': <String, Object?>{
      'ibashoApi': '^1.0',
      'minIbasho': '0.9.0',
    },
    'entry': type == 'content-pack'
        ? <String, Object?>{'content': 'content/data.json'}
        : <String, Object?>{'url': 'https://example.com/'},
    'permissions': <Object?>[],
    'assets': <String, Object?>{'icon': 'icon.png'},
  };

  test('acepta un content-pack mínimo', () {
    final manifest = parser.parseMap(validManifest());
    expect(manifest.id, 'com.justmre.demo');
    expect(manifest.type, ExtensionType.contentPack);
    expect(manifest.version, const SemVersion(1, 0, 0));
  });

  test('rechaza ID Unicode o sin DNS inverso', () {
    final raw = validManifest()..['id'] = 'Íngrimo';
    expect(() => parser.parseMap(raw), throwsA(isA<ExtensionException>()));
  });

  test('rechaza URL http', () {
    final raw = validManifest(type: 'external-app');
    raw['entry'] = <String, Object?>{'url': 'http://example.com'};
    expect(() => parser.parseMap(raw), throwsA(isA<ExtensionException>()));
  });

  test('rechaza capability reservada', () {
    final raw = validManifest()..['permissions'] = <Object?>['firebase.read'];
    expect(
      () => parser.parseMap(raw),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.forbiddenCapability,
        ),
      ),
    );
  });

  test('rechaza capability desconocida', () {
    final raw = validManifest()..['permissions'] = <Object?>['weather.read'];
    expect(
      () => parser.parseMap(raw),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.unknownCapability,
        ),
      ),
    );
  });

  test('integrated-app exige allowedOrigins', () {
    final raw = validManifest(type: 'integrated-app');
    expect(() => parser.parseMap(raw), throwsA(isA<ExtensionException>()));
  });

  test('rechaza traversal en content', () {
    final raw = validManifest();
    raw['entry'] = <String, Object?>{'content': '../session.json'};
    expect(
      () => parser.parseMap(raw),
      throwsA(
        isA<ExtensionException>().having(
          (error) => error.code,
          'code',
          ExtensionErrorCode.unsafePath,
        ),
      ),
    );
  });
}
