// Ibasho — pantalla de creditos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../../core/credits.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';

/// Los mismos creditos que estan en `CREDITS.md`, dentro de la app.
class CreditsChannel extends StatelessWidget {
  const CreditsChannel({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;

    return ChannelScaffold(
      title: l.creditsTitle,
      glyph: Glyph.info,
      child: IbashoScroll(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 44),
        child: Center(
          child: SizedBox(
            width: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.creditsIntro, style: Ty.body.copyWith(color: T.inkSoft)),
                const SizedBox(height: 26),
                _Group(title: l.creditsFonts, entries: fontCredits),
                const SizedBox(height: 22),
                _Group(title: l.creditsAudio, entries: audioCredits),
                const SizedBox(height: 22),
                _Group(title: l.creditsSoftware, entries: softwareCredits),
                const SizedBox(height: 28),
                _Licence(text: l.creditsAppLicense),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.entries});

  final String title;
  final List<CreditEntry> entries;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: title,
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const Hairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entries[i].title, style: Ty.body),
                    const SizedBox(height: 3),
                    Text(entries[i].author, style: Ty.caption),
                    if (entries[i].note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          entries[i].note!(L.of(context)!),
                          style: Ty.micro,
                        ),
                      ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _LicenceChip(label: entries[i].license),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entries[i].url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.micro,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

class _LicenceChip extends StatelessWidget {
  const _LicenceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 10,
      tint: skin.accent,
      elevation: .5,
      borderColor: skin.accentDeep,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: Ty.micro.copyWith(
          color: T.onAccent,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _Licence extends StatelessWidget {
  const _Licence({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => GlossSurface(
        radius: 20,
        recessed: true,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Row(
          children: [
            const GlyphIcon(Glyph.keycard, size: 24, color: T.inkSoft),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: Ty.caption.copyWith(color: T.ink))),
          ],
        ),
      );
}
