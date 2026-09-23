// Ibasho — el Catalogo del pinball: pedir una categoria y una rareza, y ver
// que queda por coleccionar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Cada bola jugada en el pinball sube el contador; en la numero 70 llega al
// deposito una bola dirigida de lo pedido, que da un premio que aun no se
// tenga (si ya estan todos, puede salir repetido).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/gacha.dart';
import '../../backend/prizes.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/screens/channels/gacha_channel.dart' show categoryName;
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gacha_art.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/prize_view.dart';

/// Lo que se puede tocar en el Catalogo: crece un poco al pasar por encima.
class _Tap extends StatelessWidget {
  const _Tap({super.key, required this.child, this.onPressed, this.semanticLabel});

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final reduced = IbashoSkin.of(context).reducedMotion;
    return Pressable(
      onPressed: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      builder: (context, state) {
        final scale = reduced ? 1.0 : 1 + .03 * state.hover - .05 * state.press;
        return Opacity(
          opacity: state.enabled ? 1 : .55,
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

/// La barra del Catalogo: lo pedido y cuantas bolas faltan.
class PinballWishBar extends StatelessWidget {
  const PinballWishBar({super.key, required this.wish, required this.onPressed});

  final GachaWish? wish;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final w = wish;
    final done = w == null ? 0 : w.count % wishPulls;

    return _Tap(
      key: const ValueKey<String>('pinball.catalog'),
      onPressed: onPressed,
      semanticLabel: l.gachaCatalog,
      child: GlossSurface(
        radius: 18,
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const ArtIconView(ArtIcon.catalog, size: 22),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    w == null ? l.gachaWishNone : '${categoryName(l, w.category)} · ${w.rarity.label}',
                    style: Ty.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$done/$wishPulls',
                  style: Ty.numeral(14, weight: FontWeight.w700).copyWith(color: T.inkSoft),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    const Positioned.fill(child: ColoredBox(color: T.wellTop)),
                    FractionallySizedBox(
                      widthFactor: (done / wishPulls).clamp(0.0, 1.0),
                      child: ColoredBox(color: w == null ? T.hairline : skin.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Elegir que se pide: una categoria con premios y una rareza hasta UR. Con
/// las dos elegidas se ve lo que hay de esa rareza, lo que ya se tiene en
/// color y lo que falta en silueta.
class PinballCatalogDialog extends ConsumerStatefulWidget {
  const PinballCatalogDialog({super.key});

  @override
  ConsumerState<PinballCatalogDialog> createState() => _PinballCatalogDialogState();
}

class _PinballCatalogDialogState extends ConsumerState<PinballCatalogDialog> {
  GachaCategory? _category;
  Rarity? _rarity;

  @override
  void initState() {
    super.initState();
    final wish = ref.read(gachaProvider).wish;
    _category = wish?.category;
    _rarity = wish?.rarity;
  }

  Future<void> _save() async {
    final l = L.of(context)!;
    final category = _category;
    final rarity = _rarity;
    if (category == null || rarity == null) return;
    final ok = await ref.read(gachaProvider.notifier).setWish(category, rarity);
    if (!mounted) return;
    Navigator.of(context).pop();
    showIbashoToast(context, ok ? l.gachaWishDone : l.gachaErrorPull, isError: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;
    final gacha = ref.watch(gachaProvider);
    final category = _category;
    final rarity = _rarity;
    final items = category == null || rarity == null ? const <PrizeItem>[] : prizeItemsOf(category, rarity);
    final owned = items.where((i) => gacha.owns(i.key)).length;

    return IbashoDialog(
      title: l.gachaCatalog,
      width: tall ? 360 : 540,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.gachaCatalogBody, style: (tall ? Ty.caption : Ty.body).copyWith(color: T.inkSoft)),
          const SizedBox(height: 12),
          Text(l.gachaCategory, style: Ty.micro.copyWith(color: T.inkSoft)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in GachaCategory.values)
                if (hasPrizes(c))
                  _Tap(
                    key: ValueKey<String>('gacha.wish.${c.name}'),
                    onPressed: () => setState(() => _category = c),
                    semanticLabel: categoryName(l, c),
                    child: GlossSurface(
                      radius: 14,
                      tint: _category == c ? IbashoSkin.of(context).accent : null,
                      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CategoryArtView(c, size: tall ? 26 : 30),
                          const SizedBox(width: 6),
                          Text(categoryName(l, c), style: Ty.label),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          Text(l.gachaRarity, style: Ty.micro.copyWith(color: T.inkSoft)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in Rarity.values)
                if (canWish(r))
                  _Tap(
                    key: ValueKey<String>('gacha.rarity.${r.name}'),
                    onPressed: () => setState(() => _rarity = r),
                    semanticLabel: r.label,
                    child: RarityBadge(r, height: 30, faded: _rarity != r),
                  ),
            ],
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l.pinballCatalogOwned(owned, items.length),
              key: const ValueKey<String>('pinball.catalog.owned'),
              style: Ty.micro.copyWith(color: T.inkSoft),
            ),
            const SizedBox(height: 6),
            GlossSurface(
              radius: 16,
              recessed: true,
              tint: RarityArt.of(rarity!),
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final item in items)
                    Semantics(
                      label: gacha.owns(item.key) ? l.prizeName(item.key) : '???',
                      child: PrizeView(item, size: tall ? 38 : 44, locked: !gacha.owns(item.key)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        IbashoButton(
          key: const ValueKey<String>('gacha.wish.save'),
          label: l.gachaWishSave,
          tone: ButtonTone.accent,
          onPressed: category == null || rarity == null ? null : () => unawaited(_save()),
        ),
      ],
    );
  }
}
