// Ibasho — pruebas de backdrop-pack declarativo de Kōbō.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/backdrop_pack.dart';

void main() {
  test('parsea un backdrop-pack válido', () {
    final values = parseBackdropPackText(
      '''{
        "format": 1,
        "kind": "backdrop-pack",
        "backdrops": [{
          "id": "night",
          "name": {"es": "Noche Kōbō", "en": "Kōbō Night"},
          "colors": {
            "top": "#0B1730",
            "base": "#263A63",
            "deep": "#11182F",
            "accent": "#72D7FF"
          },
          "dark": true,
          "motif": "stars"
        }]
      }''',
      extensionId: 'com.justmre.kobo-night',
      extensionVersion: '1.0.0',
    );

    expect(values, hasLength(1));
    expect(values.single.preferenceId, 'ext:com.justmre.kobo-night:night');
    expect(values.single.extensionVersion, '1.0.0');
    expect(values.single.motif, ExtensionBackdropMotif.stars);
    expect(values.single.dark, isTrue);
  });

  test('ignora content-pack de otro tipo', () {
    final values = parseBackdropPackText(
      '{"format":1,"kind":"stickers","items":[]}',
      extensionId: 'com.example.other',
      extensionVersion: '1.0.0',
    );
    expect(values, isEmpty);
  });

  test('rechaza ids duplicados y colores no declarativos', () {
    expect(
      () => parseBackdropPackText(
        '''{
          "format": 1,
          "kind": "backdrop-pack",
          "backdrops": [
            {
              "id": "night",
              "name": {"es": "Uno", "en": "One"},
              "colors": {"top":"#000000","base":"#111111","deep":"#222222","accent":"#ffffff"},
              "motif":"stars"
            },
            {
              "id": "night",
              "name": {"es": "Dos", "en": "Two"},
              "colors": {"top":"red","base":"#111111","deep":"#222222","accent":"#ffffff"},
              "motif":"haze"
            }
          ]
        }''',
        extensionId: 'com.example.duplicate',
        extensionVersion: '1.0.0',
      ),
      throwsFormatException,
    );
  });
}
