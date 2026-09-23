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
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/widgets/backdrop_art.dart';
import 'package:ibasho/ui/widgets/channel_art.dart';
import 'package:ibasho/ui/widgets/gacha_art.dart';
import 'package:ibasho/ui/widgets/gift_face.dart';
import 'package:ibasho/backend/backdrops.dart';
import 'package:ibasho/backend/gacha.dart';

void main() {
  testWidgets('ilustraciones', (tester) async {
    tester.view.physicalSize = const Size(2500, 1020);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget cell(Widget child) => Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(width: 140, height: 140, child: child),
    );

    Widget backdropCell(String id) => Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 140, height: 140, child: BackdropView(id: id)),
      ),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        child: IbashoSkin(
          accent: T.cyan,
          reducedMotion: false,
          child: ColoredBox(
            color: T.shellBottom,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Wrap(
                    children: [
                      for (final a in ArtIcon.values)
                        cell(ArtIconView(a, size: 140)),
                    ],
                  ),
                  Row(
                    children: [
                      for (final r in Rarity.values)
                        cell(GachaBallView(r, size: 140)),
                      for (final c in GachaCategory.values)
                        cell(CategoryArtView(c, size: 140)),
                    ],
                  ),
                  Row(
                    children: [
                      for (final r in Rarity.values)
                        cell(Center(child: RarityBadge(r, height: 40))),
                    ],
                  ),
                  Row(
                    children: [
                      for (final t in [0.0, .15, .3, .45, .6, .75, .9, 1.0])
                        cell(
                          ColoredBox(
                            color: T.shellTop,
                            child: GiftFace(open: t),
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      for (final s in [24.0, 32.0, 48.0])
                        for (final a in [
                          ArtIcon.yatai,
                          ArtIcon.minesweeper,
                          ArtIcon.tsumiki,
                          ArtIcon.nihongo,
                        ])
                          Padding(
                            padding: const EdgeInsets.all(6),
                            child: ArtIconView(a, size: s),
                          ),
                    ],
                  ),
                  Row(
                    children: [for (final b in backdrops) backdropCell(b.id)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      backdrops.length,
      16,
      reason: 'falta pintar algun fondo en la galeria',
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File(
        'build/screenshots/g8-ilustraciones.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
