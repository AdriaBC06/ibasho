// Ibasho — barra de estado del panel superior.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:intl/intl.dart';

import '../../backend/models.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../state/system_status.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../widgets/glyphs.dart';
import '../widgets/pressable.dart';

/// Bateria, conexion e idioma, con la estetica de los indicadores de 3DS.
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final skin = IbashoSkin.of(context);
    final preferences = ref.watch(preferencesProvider);
    final coins = ref.watch(coinsProvider);

    final bars = switch (status.link) {
      LinkQuality.offline => 0,
      LinkQuality.weak => 1,
      LinkQuality.fair => 2,
      LinkQuality.strong => 3,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Las monedas van las primeras, antes de los indicadores del aparato:
        // son de la cuenta, no del cacharro. Hoy estan a cero para todo el
        // mundo y aun asi se enseñan, porque el sitio tiene que existir antes
        // de que haya algo que gastar.
        _CoinsReadout(coins: coins, accent: skin.accentDeep, compact: compact),
        SizedBox(width: compact ? 16 : 22),
        // Sin bateria no se dibuja nada ni se deja hueco.
        if (status.battery != null) ...[
          _BatteryReadout(battery: status.battery!, accent: skin.accent),
          SizedBox(width: compact ? 16 : 22),
        ],
        SignalArcs(
          bars: bars,
          color: bars == 0 ? T.warn : skin.accentDeep,
          dim: T.hairline,
          size: compact ? 16 : 18,
        ),
        SizedBox(width: compact ? 12 : 16),
        _LocaleButton(
          code: preferences.localeCode,
          onPressed: () =>
              changeLanguage(ref, preferences.localeCode == 'es' ? 'en' : 'es'),
        ),
      ],
    );
  }
}

/// El monedero, con el mismo peso visual que la bateria: glifo y cifra.
class _CoinsReadout extends StatelessWidget {
  const _CoinsReadout({
    required this.coins,
    required this.accent,
    required this.compact,
  });

  final int coins;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Semantics(
      label: '$coins ${l.coinsLabel}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(
            Glyph.coin,
            size: compact ? 15 : 17,
            // El acento, no la tinta suave: es lo unico de la barra que crece
            // con lo que haces, y tiene que verse que esta vivo.
            color: accent,
            strokeWidth: 1.7,
          ),
          const SizedBox(width: 7),
          Text(
            // Con separador de millares: en cuanto haya algo que gastar, un
            // "1.250" se lee de un vistazo y un "1250" no.
            NumberFormat.decimalPattern(
              Localizations.localeOf(context).languageCode,
            ).format(coins),
            style: Ty.numeral(15, color: T.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _BatteryReadout extends StatelessWidget {
  const _BatteryReadout({required this.battery, required this.accent});

  final BatteryInfo battery;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BatteryGauge(
            level: battery.level,
            charging: battery.charging,
            color: T.inkSoft,
            accent: accent,
            warn: T.warn,
          ),
          const SizedBox(width: 8),
          Text(
            '${battery.level}%',
            style: Ty.numeral(15, color: T.inkSoft),
          ),
        ],
      );
}

/// Codigo de dos letras del idioma activo, pulsable para cambiarlo.
class _LocaleButton extends StatelessWidget {
  const _LocaleButton({required this.code, required this.onPressed});

  final String code;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: code,
      builder: (context, state) => FocusRing(
        visible: state.focus,
        radius: 9,
        inset: -3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            code.toUpperCase(),
            style: Ty.numeral(
              15,
              color: Color.lerp(T.inkSoft, skin.accentDeep, state.hover)!,
              weight: FontWeight.w700,
            ).copyWith(letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}
