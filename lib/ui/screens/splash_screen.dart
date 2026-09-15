// Ibasho — pantalla de arranque.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../widgets/gloss.dart';
import '../widgets/logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  double _stagger(double start, double end, Curve curve) =>
      CurvedAnimation(parent: _entry, curve: Interval(start, end, curve: curve))
          .value;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    return Bezel(
      child: AnimatedBuilder(
        animation: _entry,
        builder: (context, _) {
          final mark = skin.reducedMotion ? 1.0 : _stagger(0, .55, Curves.easeOutBack);
          final word = skin.reducedMotion ? 1.0 : _stagger(.22, .72, Curves.easeOut);
          final kanji = skin.reducedMotion ? 1.0 : _stagger(.44, 1, Curves.easeOut);

          return Stack(
            alignment: Alignment.center,
            children: [
              // Halo de acento detras del logotipo.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.12),
                      radius: .62,
                      colors: [
                        skin.accent.withValues(alpha: .26 * word),
                        skin.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: mark.clamp(0, 1),
                    child: Transform.scale(
                      scale: .82 + .18 * mark,
                      child: IbashoMark(size: 168, accent: skin.accent),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Opacity(
                    opacity: word.clamp(0, 1),
                    child: Transform.translate(
                      offset: Offset(0, 14 * (1 - word)),
                      child: Text(l.appName, style: Ty.logo(62, T.ink)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: kanji.clamp(0, 1),
                    child: Text('居場所', style: Ty.logoJa(30, T.inkSoft)),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: (kanji * .9).clamp(0, 1),
                    child: Text(
                      l.appTagline,
                      style: Ty.caption.copyWith(letterSpacing: 3.4),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
