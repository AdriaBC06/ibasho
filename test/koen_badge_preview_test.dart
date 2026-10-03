// Ibasho — hoja de prueba de la insignia de amistad del parque.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Deja `build/screenshots/koen-insignia.png`: los cinco niveles a 22, 26 y
// 72 px, y la pastilla del perfil.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/koen_bonds.dart';
import 'package:ibasho/games/koen/koen_badge.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';

void main() {
  testWidgets('la insignia de amistad, en todos los niveles', (tester) async {
    tester.view.physicalSize = const Size(900, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('es'),
        delegates: L.localizationsDelegates,
        child: RepaintBoundary(
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
                      for (final size in const [22.0, 26.0, 72.0]) ...[
                        Row(
                          children: [
                            for (final level in KoenFriendLevel.values) ...[
                              KoenFriendBadge(level: level, size: size),
                              const SizedBox(width: 24),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Wrap(
                        spacing: 10,
                        children: [
                          for (final level in KoenFriendLevel.values.skip(1)) KoenFriendChip(level: level),
                        ],
                      ),
                    ],
                  ),
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
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/screenshots').createSync(recursive: true);
      File('build/screenshots/koen-insignia.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
