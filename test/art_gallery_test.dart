// Ibasho — galeria de las ilustraciones: iconos pintados y el regalo abriendose.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja `build/screenshots/g8-ilustraciones.png` para mirarla a ojo.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/widgets/channel_art.dart';
import 'package:ibasho/ui/widgets/gift_face.dart';

void main() {
  testWidgets('ilustraciones', (tester) async {
    tester.view.physicalSize = const Size(1600, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget cell(Widget child) => Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(width: 140, height: 140, child: child),
        );

    await tester.pumpWidget(
      RepaintBoundary(
        child: ColoredBox(
          color: T.shellBottom,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                Row(children: [for (final a in ArtIcon.values) cell(ArtIconView(a, size: 140))]),
                Row(children: [
                  for (final t in [0.0, .15, .3, .45, .6, .75, .9, 1.0])
                    cell(ColoredBox(color: T.shellTop, child: GiftFace(open: t))),
                ]),
                Row(children: [
                  for (final s in [24.0, 32.0, 48.0])
                    for (final a in [ArtIcon.yatai, ArtIcon.minesweeper, ArtIcon.tsumiki, ArtIcon.nihongo])
                      Padding(padding: const EdgeInsets.all(6), child: ArtIconView(a, size: s)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/g8-ilustraciones.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
