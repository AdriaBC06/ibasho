// Ibasho — la rejilla de canales: cada pagina se compone entera y se toca.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/theme/skin.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/screens/channel_grid.dart';
import 'package:ibasho/ui/screens/channels/channel.dart';
import 'package:ibasho/ui/widgets/glyphs.dart';
import 'package:ibasho/l10n/gen/app_localizations.dart';
import 'package:ibasho/ui/canvas.dart';
import 'package:ibasho/ui/widgets/slot_tile.dart';

void main() {
  testWidgets(
    'la pagina 2 se completa con ranuras y sus canales se pueden tocar',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final opened = <String>[];
      final channels = <ChannelSpec>[
        for (var i = 0; i < 10; i++)
          ChannelSpec(
            id: 'c$i',
            glyph: Glyph.mine,
            label: (l) => 'Canal $i',
            builder: (_) {
              opened.add('c$i');
              return const SizedBox.shrink();
            },
          ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          child: WidgetsApp(
            color: T.cyan,
            locale: const Locale('es'),
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            pageRouteBuilder: <R>(RouteSettings s, WidgetBuilder b) =>
                PageRouteBuilder<R>(
                  settings: s,
                  pageBuilder: (c, a, b2) => b(c),
                  transitionDuration: Duration.zero,
                ),
            builder: (context, navigator) => IbashoSkin(
              accent: T.cyan,
              reducedMotion: true,
              child: VirtualCanvas(child: navigator!),
            ),
            home: ChannelGrid(
              channels: channels,
              page: 1,
              height: 380,
              width: 1200,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pagina 2: dos canales y seis ranuras libres, como una pagina de 4x2.
      expect(find.byType(EmptySlot), findsNWidgets(6));
      await tester.tap(find.text('Canal 9'));
      await tester.pumpAndSettle();
      expect(opened, contains('c9'));
    },
  );
}
