// Ibasho — canal de ranura libre.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../channel_route.dart';

/// Lo que hay detras de una ranura libre.
///
/// No hace nada: existe para poder juzgar el gesto de apertura antes de que
/// haya apps de verdad.
class ComingSoonChannel extends StatelessWidget {
  const ComingSoonChannel({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    return ChannelScaffold(
      title: l.comingSoonTitle,
      glyph: Glyph.slot,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 168,
              height: 168,
              child: GlossSurface(
                radius: 42,
                recessed: true,
                child: Center(
                  child: GlyphIcon(
                    Glyph.slot,
                    size: 78,
                    color: skin.accent.withValues(alpha: .6),
                    strokeWidth: 2.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 34),
            Text(
              l.comingSoonBody,
              textAlign: TextAlign.center,
              style: Ty.lead.copyWith(color: T.inkSoft, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}
