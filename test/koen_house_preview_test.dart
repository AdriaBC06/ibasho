// Ibasho — hoja de prueba de la casita de un dúo de Tama Kōen.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja `build/screenshots/koen-casita.png`: la casita en los niveles 1 y 5,
// con todos los muebles puestos, y los muebles sueltos como en el selector.
// Y `build/screenshots/koen-pareja.png`: el accesorio de pareja.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/koen_duo.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/backend/prizes.dart' show prizeItem;
import 'package:ibasho/games/koen/koen_charm.dart';
import 'package:ibasho/games/koen/koen_house.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/tama/tama_outfit.dart' show PrizeArt;
import 'package:ibasho/ui/tama/tama_view.dart';

Tama _tama(String id, String creator, String carer, String color, int body) => Tama(
  id: id,
  creator: creator,
  keeper: creator,
  carer: carer,
  name: id,
  look: TamaLook(parts: {TamaPart.body: body, TamaPart.crown: body + 1}, color: color),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  testWidgets('la casita de un dúo, con todos los muebles', (tester) async {
    tester.view.physicalSize = const Size(1500, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final duo = KoenDuo(
      me: 'me',
      friend: 'f',
      mine: [_tama('a', 'me', 'f', '#5BC8F5', 0)],
      theirs: [_tama('b', 'f', 'me', '#F79A68', 2)],
    );
    final full = duo.copyWith(
      data: KoenDuoData(decor: {for (var i = 0; i < 6; i++) i: KoenFurniture.values[i == 4 ? 2 : (i == 2 ? 6 : i)]}),
    );
    final first = duo.copyWith(data: const KoenDuoData(decor: {0: KoenFurniture.andon, 1: KoenFurniture.zabuton}));
    await tester.pumpWidget(
      RepaintBoundary(
        child: IbashoSkin(
          accent: T.cyan,
          reducedMotion: false,
          child: ColoredBox(
          color: T.shellBottom,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(width: 700, child: KoenHouseView(duo: first, level: 1)),
                      const SizedBox(width: 20),
                      SizedBox(width: 700, child: KoenHouseView(duo: full, level: 5)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(children: [for (final f in KoenFurniture.values) KoenFurnitureView(f, size: 150)]),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/koen-casita.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });

  testWidgets('el accesorio de pareja, en la casita', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final code = koenCharmCode(koenDuoKey('me', 'f'));
    await tester.runAsync(() => PrizeArt.instance.preload([
      for (final shape in KoenCharm.values)
        for (final left in const [true, false]) prizeItem(koenCharmKey(shape, left: left, code: code))!,
    ]));
    KoenDuo duo(KoenCharm shape, int a, int b) => KoenDuo(
      me: 'me',
      friend: 'f',
      mine: [_tama('a', 'me', 'f', '#5BC8F5', a)],
      theirs: [_tama('b', 'f', 'me', '#F79A68', b)],
      data: KoenDuoData(charm: KoenCharmChoice(shape, code), decor: const {0: KoenFurniture.andon}),
      demo: true,
    );
    Widget alone(KoenCharm shape, bool left, bool mirror) {
      var look = koenWithCharm(_tama('c', 'me', 'f', '#9AD873', 4).look, koenCharmKey(shape, left: left, code: code))!;
      if (mirror) look = koenMirrorCharm(look);
      return SizedBox(
        width: 120,
        height: 120,
        child: Transform.flip(flipX: mirror, child: TamaView(look: look, personality: TamaPersonality.calm, name: 'c', size: 120)),
      );
    }

    await tester.pumpWidget(
      RepaintBoundary(
        child: IbashoSkin(
          accent: T.cyan,
          reducedMotion: false,
          child: ColoredBox(
            color: T.shellBottom,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (final (i, shape) in KoenCharm.values.indexed) ...[
                          if (i > 0) const SizedBox(width: 20),
                          SizedBox(
                            width: 470,
                            child: KoenHouseView(duo: duo(shape, i, i + 3), level: 1, demoWorn: true),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        for (final shape in KoenCharm.values) ...[
                          KoenCharmPairView(charm: KoenCharmChoice(shape, code), size: 90),
                          const SizedBox(width: 30),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    // En el parque: la mitad derecha mirando a la izquierda (en
                    // espejo) tiene que seguir mirando al otro.
                    Row(
                      children: [
                        for (final shape in KoenCharm.values) ...[
                          alone(shape, true, false),
                          alone(shape, false, true),
                          const SizedBox(width: 30),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/koen-pareja.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
