// Ibasho — hoja de prueba de los premios del gacha puestos en Tamas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja `build/screenshots/g9-premios.png`: cada premio en seis Tamas de formas,
// coronillas y medidas distintas (una variante de color por Tama), y una fila
// con varios puestos a la vez. Los pinta el pintor del Tama, como en la app.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/prizes.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/tama/tama_outfit.dart';
import 'package:ibasho/ui/tama/tama_painter.dart';

final List<TamaLook> _looks = [
  const TamaLook(parts: {TamaPart.body: 0, TamaPart.crown: 1}, color: '#5BC8F5'),
  const TamaLook(
    parts: {TamaPart.body: 1, TamaPart.crown: 2, TamaPart.eyes: 2},
    dials: {TamaDial.bodyWidth: 80, TamaDial.bodyHeight: 30},
    color: '#F79A68',
  ),
  const TamaLook(
    parts: {TamaPart.body: 2, TamaPart.crown: 3, TamaPart.eyes: 4},
    dials: {TamaDial.eyeSize: 90, TamaDial.eyeSpacing: 20},
    color: '#74DDA2',
  ),
  const TamaLook(
    parts: {TamaPart.body: 3, TamaPart.crown: 4, TamaPart.arms: 2},
    dials: {TamaDial.bodyHeight: 85, TamaDial.eyeHeight: 20},
    color: '#C9A4EE',
  ),
  const TamaLook(
    parts: {TamaPart.body: 4, TamaPart.crown: 5, TamaPart.feet: 2},
    dials: {TamaDial.bodyWidth: 100, TamaDial.eyeSpacing: 90},
    color: '#F6A8D0',
  ),
  const TamaLook(
    parts: {TamaPart.body: 5, TamaPart.crown: 0, TamaPart.eyes: 1},
    dials: {TamaDial.bodyWidth: 15, TamaDial.bodyHeight: 100, TamaDial.eyeSize: 10},
    color: '#F3D95A',
  ),
];

/// Un Tama con [worn] puestos, pintado por el pintor de verdad.
Widget _dressed(TamaLook look, List<String> worn, double side) {
  var outfit = TamaOutfit.none;
  for (final key in worn) {
    outfit = outfit.toggle(prizeItem(key)!)!;
  }
  return SizedBox(
    width: side,
    height: side,
    child: CustomPaint(painter: TamaPainter(look: look.withOutfit(outfit))),
  );
}

void main() {
  testWidgets('premios puestos', (tester) async {
    const side = 150.0;
    // Una fila por premio, con una variante distinta en cada Tama, y al final
    // unas cuantas combinaciones.
    final rows = <List<List<String>>>[
      for (final p in wearablePrizes)
        [
          for (var i = 0; i < _looks.length; i++) ['${p.id}_${p.variants[i % p.variants.length]}'],
        ],
      [
        ['angel_wings_white', 'crown_gold', 'bowtie_red'],
        ['hood_black', 'shutter_shades_lime', 'sneakers_green'],
        ['beanie_red', 'glasses_navy', 'bottle_water'],
        ['headphones_skyblue', 'bandage_stars', 'sneakers_blue'],
        ['afro_brown', 'groucho_black', 'bowtie_black'],
        ['angel_wings_black', 'beret_black', 'clown_nose_green'],
      ],
      [
        ['cape_red', 'mask_c', 'sword_diamond'],
        ['randoseru_red', 'cap_yellow', 'balloon_pink'],
        ['swim_ring_stripes', 'shutter_shades_orange', 'boba_pink'],
        ['fairies_light', 'crown_silver', 'controller_blue'],
        ['scarf_cream', 'beanie_blue', 'taco_classic'],
        ['rgb_wings_rainbow', 'rgb_shades_rainbow', 'energy_green'],
      ],
    ];
    const perRow = 6;
    tester.view.physicalSize = Size(side * perRow * 2 + 100, side * (rows.length / 2).ceil() + 40);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget row(List<List<String>> cells) =>
        Row(children: [for (var i = 0; i < cells.length; i++) _dressed(_looks[i], cells[i], side)]);

    await tester.pumpWidget(
      RepaintBoundary(
        child: ColoredBox(
          color: T.shellBottom,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(20),
              // Dos columnas de filas, para que la hoja no sea una tira.
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final half in [
                  rows.sublist(0, (rows.length / 2).ceil()),
                  rows.sublist((rows.length / 2).ceil()),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Column(children: [for (final r in half) row(r)]),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
    // Los SVG se leen y se compilan fuera del reloj falso de los tests.
    await tester.runAsync(() => PrizeArt.instance.preload([for (final p in wearablePrizes) ...p.items]));
    await tester.pump();

    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/g9-premios.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
