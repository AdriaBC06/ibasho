// Ibasho — canal del Yatai: la tienda, al estilo Canal Tienda Wii / eShop.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/shop.dart';
import '../../../backend/tama.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/pantry.dart';
import '../../../state/providers.dart';
import '../../../state/shop.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../tama/tama_food.dart';
import '../../tama/tama_text.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/slot_tile.dart';
import '../channel_route.dart';

/// Las tres pestañas de abajo, en el mismo orden que en el catalogo.
enum _Tab { games, tamas, gacha }

/// El icono de un juego. De momento solo hay uno; cuando haya mas, esto crece
/// con ellos igual que `gameChannelRegistry` en `channel.dart`.
Glyph _gameGlyph(String gameId) => switch (gameId) {
  'minesweeper' => Glyph.mine,
  _ => Glyph.play,
};

String _gameTitle(L l, String gameId) => switch (gameId) {
  'minesweeper' => l.minesweeperTitle,
  _ => gameId,
};

/// El canal de la tienda, montado como el propio entorno: dos pantallas.
///
/// Arriba, el escaparate con el articulo elegido en grande, su descripcion,
/// el precio y tu saldo. Abajo, las pestañas Juegos / Tamas / Gacha y la
/// rejilla de articulos. Comprar abre una confirmacion (con cantidad para la
/// comida) y una descarga falsa al estilo del Canal Tienda de Wii.
class YataiChannel extends ConsumerStatefulWidget {
  const YataiChannel({super.key});

  @override
  ConsumerState<YataiChannel> createState() => _YataiChannelState();
}

class _YataiChannelState extends ConsumerState<YataiChannel> {
  _Tab _tab = _Tab.games;
  String? _selectedId;

  List<ShopItem> _items(_Tab tab) {
    final section = switch (tab) {
      _Tab.games => ShopSection.games,
      _Tab.tamas => ShopSection.tamas,
      _Tab.gacha => ShopSection.gacha,
    };
    return shopCatalog
        .where((i) => i.section == section)
        .toList(growable: false);
  }

  void _setTab(_Tab tab) {
    if (tab == _tab) return;
    AudioService.instance.play(Sfx.tick);
    final items = _items(tab);
    setState(() {
      _tab = tab;
      _selectedId = items.isEmpty ? null : items.first.id;
    });
  }

  void _select(ShopItem item) {
    if (item.id == _selectedId) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _selectedId = item.id);
  }

  Future<void> _buy(ShopItem item) async {
    final l = L.of(context)!;
    final shop = ref.read(shopProvider);
    final coins = ref.read(coinsProvider);
    final price = shop.prices[item.id];
    if (price == null) return;

    var qty = 1;
    if (item.food != null) {
      final picked = await showIbashoModal<int>(
        context,
        (context) =>
            _QuantityDialog(food: item.food!, price: price, coins: coins),
      );
      if (picked == null) return;
      qty = picked;
    } else {
      final ok = await askConfirmation(
        context,
        title: l.yataiConfirmTitle(_gameTitle(l, item.gameId!)),
        body: price == 0
            ? l.yataiConfirmBodyFree
            : l.yataiConfirmBodyPrice(price),
        confirmLabel: price == 0 ? l.yataiGet : l.yataiBuy,
        cancelLabel: l.actionCancel,
      );
      if (!ok) return;
    }

    if (!mounted) return;
    final buyFuture = ref.read(shopProvider.notifier).buy(item, qty);
    final error = await showIbashoModal<Object?>(
      context,
      (context) => _InstallingDialog(future: buyFuture),
    );
    if (!mounted) return;

    if (error != null) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, _errorMessage(l, error), isError: true);
      return;
    }
    AudioService.instance.play(Sfx.chime);
    final done = item.section == ShopSection.games
        ? l.yataiDoneGame
        : l.yataiDoneFood(qty, foodLabel(l, item.food!));
    showIbashoToast(context, done);
  }

  String _errorMessage(L l, Object error) {
    final failure = error is ShopException
        ? error.failure
        : ShopFailure.rejected;
    return switch (failure) {
      ShopFailure.noPrice => l.yataiErrorNoPrice,
      ShopFailure.insufficientCoins => l.yataiErrorInsufficientCoins,
      ShopFailure.foodLocked => l.yataiErrorFoodLocked,
      ShopFailure.alreadyOwned => l.yataiErrorAlreadyOwned,
      ShopFailure.network => l.yataiErrorNetwork,
      ShopFailure.rejected => l.yataiErrorRejected,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final shop = ref.watch(shopProvider);
    final coins = ref.watch(coinsProvider);
    final unlocked = ref.watch(unlockedFoodsProvider);
    final pantry = ref.watch(pantryProvider);

    final items = _items(_tab);
    if (_selectedId == null && items.isNotEmpty) {
      _selectedId = items.first.id;
    }
    final selected = items.isEmpty
        ? null
        : items.firstWhere(
            (i) => i.id == _selectedId,
            orElse: () => items.first,
          );

    return ChannelScaffold(
      title: l.yataiTitle,
      glyph: Glyph.yatai,
      trailing: _BalanceReadout(coins: coins),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: LayoutBuilder(
          builder: (context, box) {
            final showcase = layout.tall
                ? math.max(190.0, math.min(300.0, box.maxHeight * .38))
                : 260.0;
            return Column(
              children: [
                const SizedBox(height: 14),
                SizedBox(
                  height: showcase,
                  child: ScreenPanel(
                    child: _tab == _Tab.gacha
                        ? const _GachaShowcase()
                        : !shop.loaded
                        ? Center(child: Text(l.loading, style: Ty.lead))
                        : _Showcase(
                            item: selected,
                            shop: shop,
                            coins: coins,
                            unlocked: unlocked,
                            pantry: pantry,
                            onBuy: selected == null
                                ? null
                                : () => unawaited(_buy(selected)),
                          ),
                  ),
                ),
                SizedBox(height: layout.pick(18, 14)),
                _Tabs(tab: _tab, onChanged: _setTab),
                SizedBox(height: layout.pick(14, 10)),
                Expanded(
                  child: ScreenPanel(
                    child: _tab == _Tab.gacha
                        ? const _GachaPanel()
                        : LayoutBuilder(
                            builder: (context, box) => _ItemGrid(
                              size: box.biggest,
                              tall: layout.tall,
                              items: items,
                              selectedId: selected?.id,
                              shop: shop,
                              unlocked: unlocked,
                              pantry: pantry,
                              onSelect: _select,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}

// --- Saldo, en la cabecera --------------------------------------------------

class _BalanceReadout extends StatelessWidget {
  const _BalanceReadout({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(Glyph.coin, size: 18, color: skin.accentDeep),
        const SizedBox(width: 7),
        Text(
          NumberFormat.decimalPattern(
            Localizations.localeOf(context).languageCode,
          ).format(coins),
          style: Ty.numeral(17, color: T.inkSoft),
        ),
        const SizedBox(width: 6),
        Text(l.coinsLabel, style: Ty.caption),
      ],
    );
  }
}

// --- Pantalla de arriba: el escaparate --------------------------------------

class _Showcase extends StatelessWidget {
  const _Showcase({
    required this.item,
    required this.shop,
    required this.coins,
    required this.unlocked,
    required this.pantry,
    required this.onBuy,
  });

  final ShopItem? item;
  final ShopState shop;
  final int coins;
  final Set<TamaFood> unlocked;
  final Map<TamaFood, int> pantry;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    final tall = layout.tall;
    final it = item;
    if (it == null) return const SizedBox.shrink();

    final locked = it.food != null && !unlocked.contains(it.food);
    final owned = it.gameId != null && shop.games.containsKey(it.gameId);
    final price = shop.prices[it.id];
    final name = it.food != null
        ? foodLabel(l, it.food!)
        : _gameTitle(l, it.gameId!);
    final description = it.food != null ? l.yataiDescFood : l.yataiDescGame;

    final String actionLabel;
    final bool actionEnabled;
    if (owned) {
      actionLabel = l.yataiInstalled;
      actionEnabled = false;
    } else if (locked) {
      actionLabel = l.yataiLocked;
      actionEnabled = false;
    } else if (price == null) {
      actionLabel = l.yataiPriceNotAvailable;
      actionEnabled = false;
    } else {
      actionLabel = price == 0 ? l.yataiGet : l.yataiBuy;
      actionEnabled = !shop.busy;
    }

    final priceText = price == null
        ? l.yataiPriceNotAvailable
        : price == 0
        ? l.yataiPriceFree
        : '${NumberFormat.decimalPattern(Localizations.localeOf(context).languageCode).format(price)} ${l.coinsLabel}';

    final art = SizedBox(
      width: tall ? 104 : 180,
      height: tall ? 104 : 180,
      child: GlossSurface(
        radius: 28,
        child: Center(
          child: it.food != null
              ? CustomPaint(
                  size: Size(tall ? 76 : 130, tall ? 76 : 130),
                  painter: TamaFoodPainter(it.food!),
                )
              : GlyphIcon(
                  _gameGlyph(it.gameId!),
                  size: tall ? 52 : 88,
                  color: skin.accentDeep,
                  strokeWidth: 2.2,
                ),
        ),
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tall ? Ty.title : Ty.display,
        ),
        SizedBox(height: tall ? 3 : 6),
        Text(
          description,
          maxLines: tall ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: Ty.body.copyWith(color: T.inkSoft),
        ),
        SizedBox(height: tall ? 6 : 16),
        Text(
          priceText,
          style: Ty.body.copyWith(
            color: skin.accentDeep,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (it.food != null) ...[
          const SizedBox(height: 2),
          Text(l.yataiUnitsOwned(pantry[it.food] ?? 0), style: Ty.caption),
        ],
        if (!tall) ...[
          const SizedBox(height: 18),
          IbashoButton(
            key: const ValueKey<String>('yatai.buy'),
            label: actionLabel,
            glyph: owned ? Glyph.check : (locked ? Glyph.lock : Glyph.gift),
            tone: actionEnabled ? ButtonTone.accent : ButtonTone.plain,
            height: 48,
            minWidth: 190,
            cue: null,
            onPressed: actionEnabled ? onBuy : null,
          ),
        ],
      ],
    );

    if (tall) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  art,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SingleChildScrollView(child: info),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            IbashoButton(
              key: const ValueKey<String>('yatai.buy'),
              label: actionLabel,
              glyph: owned ? Glyph.check : (locked ? Glyph.lock : Glyph.gift),
              tone: actionEnabled ? ButtonTone.accent : ButtonTone.plain,
              height: 48,
              expand: true,
              cue: null,
              onPressed: actionEnabled ? onBuy : null,
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        SizedBox(width: 240, child: Center(child: art)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 20, 36, 20),
            child: info,
          ),
        ),
      ],
    );
  }
}

// --- Pestañas ----------------------------------------------------------------

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onChanged});

  final _Tab tab;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoSegmented<_Tab>(
      key: const ValueKey<String>('yatai.tabs'),
      options: [
        (_Tab.games, l.yataiTabGames),
        (_Tab.tamas, l.yataiTabTamas),
        (_Tab.gacha, l.yataiTabGacha),
      ],
      value: tab,
      onChanged: onChanged,
    );
  }
}

// --- Pantalla de abajo: la rejilla -------------------------------------------

class _ItemGrid extends StatelessWidget {
  const _ItemGrid({
    required this.size,
    required this.tall,
    required this.items,
    required this.selectedId,
    required this.shop,
    required this.unlocked,
    required this.pantry,
    required this.onSelect,
  });

  final Size size;
  final bool tall;
  final List<ShopItem> items;
  final String? selectedId;
  final ShopState shop;
  final Set<TamaFood> unlocked;
  final Map<TamaFood, int> pantry;
  final ValueChanged<ShopItem> onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = tall ? 3 : 6;
    const gap = 16.0;
    final pad = tall ? 16.0 : 24.0;
    final tileW = (size.width - pad * 2 - gap * (columns - 1)) / columns;
    final tileH = math.min(tileW * 1.05, 118.0);

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            _ShopTile(
              key: ValueKey<String>('yatai.item.${item.id}'),
              item: item,
              width: tileW,
              height: tileH,
              selected: item.id == selectedId,
              shop: shop,
              unlocked: unlocked,
              pantry: pantry,
              onPressed: () => onSelect(item),
            ),
        ],
      ),
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    required this.selected,
    required this.shop,
    required this.unlocked,
    required this.pantry,
    required this.onPressed,
  });

  final ShopItem item;
  final double width;
  final double height;
  final bool selected;
  final ShopState shop;
  final Set<TamaFood> unlocked;
  final Map<TamaFood, int> pantry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final locked = item.food != null && !unlocked.contains(item.food);
    final owned = item.gameId != null && shop.games.containsKey(item.gameId);
    final name = item.food != null
        ? foodLabel(l, item.food!)
        : _gameTitle(l, item.gameId!);

    return SlotTile(
      width: width,
      height: height,
      selected: selected,
      onPressed: onPressed,
      semanticLabel: locked ? '$name · ${l.yataiLocked}' : name,
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: Opacity(
                    opacity: locked ? .38 : 1,
                    child: item.food != null
                        ? CustomPaint(
                            size: Size(height * .5, height * .5),
                            painter: TamaFoodPainter(item.food!),
                          )
                        : GlyphIcon(
                            _gameGlyph(item.gameId!),
                            size: height * .4,
                            color: T.ink,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Ty.caption.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (locked)
            const Positioned(
              right: 6,
              bottom: 26,
              child: GlyphIcon(Glyph.lock, size: 15, color: T.inkSoft),
            ),
          if (owned)
            Positioned(left: 6, top: 6, child: _Badge(text: l.yataiInstalled)),
          if (item.food != null && !locked)
            Positioned(
              right: 6,
              top: 6,
              child: _Badge(text: '${pantry[item.food] ?? 0}'),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 9,
      tint: skin.accent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      child: Text(
        text,
        style: Ty.micro.copyWith(
          color: T.onAccent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// --- Gacha: proximamente ------------------------------------------------------

class _GachaShowcase extends StatelessWidget {
  const _GachaShowcase();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    // En vertical el escaparate es bajo: la maquina encoge con el hueco para
    // que el texto quepa debajo.
    return LayoutBuilder(
      builder: (context, box) {
        final pad = math.min(24.0, box.maxHeight * .08);
        final machine = math.min(96.0, box.maxHeight * .36);
        return Center(
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CapsuleMachine(size: machine),
                SizedBox(height: pad * .5),
                Text(l.yataiGachaTitle, style: Ty.title),
                const SizedBox(height: 6),
                Flexible(
                  child: Text(
                    l.yataiGachaBody,
                    style: Ty.body.copyWith(color: T.inkSoft),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GachaPanel extends StatelessWidget {
  const _GachaPanel();

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Opacity(
      opacity: .55,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _CapsuleMachine(size: 120),
            const SizedBox(height: 12),
            Text(l.yataiGachaTitle, style: Ty.lead),
          ],
        ),
      ),
    );
  }
}

/// Una maquina expendedora de capsulas, dibujada a mano: cupula de cristal
/// sobre una base, con unas cuantas capsulas dentro.
class _CapsuleMachine extends StatelessWidget {
  const _CapsuleMachine({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _CapsuleMachinePainter(IbashoSkin.of(context).accent),
    ),
  );
}

class _CapsuleMachinePainter extends CustomPainter {
  _CapsuleMachinePainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .028
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = T.inkSoft;

    final domeCentre = Offset(size.width / 2, size.height * .4);
    final domeRadius = s * .32;
    // La cupula.
    canvas.drawArc(
      Rect.fromCircle(center: domeCentre, radius: domeRadius),
      math.pi,
      math.pi,
      false,
      stroke,
    );
    canvas.drawLine(
      Offset(domeCentre.dx - domeRadius, domeCentre.dy),
      Offset(domeCentre.dx - domeRadius, domeCentre.dy + s * .22),
      stroke,
    );
    canvas.drawLine(
      Offset(domeCentre.dx + domeRadius, domeCentre.dy),
      Offset(domeCentre.dx + domeRadius, domeCentre.dy + s * .22),
      stroke,
    );
    // La base.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          domeCentre.dx - domeRadius - s * .04,
          domeCentre.dy + s * .22,
          domeRadius * 2 + s * .08,
          s * .26,
        ),
        Radius.circular(s * .05),
      ),
      stroke,
    );
    // Unas capsulas dentro de la cupula.
    final capsules = Paint()..color = accent.withValues(alpha: .8);
    for (final (dx, dy, r) in [
      (-.14, .06, .09),
      (.02, -.04, .1),
      (.15, .08, .08),
      (-.02, .16, .085),
    ]) {
      canvas.drawCircle(domeCentre + Offset(dx * s, dy * s), r * s, capsules);
    }
    // La ranura de sacar la capsula.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(domeCentre.dx, domeCentre.dy + s * .35),
          width: s * .18,
          height: s * .08,
        ),
        Radius.circular(s * .02),
      ),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_CapsuleMachinePainter old) => old.accent != accent;
}

// --- Dialogos ------------------------------------------------------------------

/// El paso de cantidad, para la comida: ×1, ×5 o ×10, con el total.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.food,
    required this.price,
    required this.coins,
  });

  final TamaFood food;
  final int price;
  final int coins;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  static const List<int> _options = [1, 5, 10];
  late int _qty = _options.firstWhere(
    (q) => widget.price * q <= widget.coins,
    orElse: () => 1,
  );

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final total = widget.price * _qty;

    return IbashoDialog(
      title: l.yataiConfirmTitle(foodLabel(l, widget.food)),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.price == 0
                ? l.yataiConfirmBodyFree
                : l.yataiConfirmBodyPrice(widget.price),
            style: Ty.body.copyWith(color: T.inkSoft),
          ),
          const SizedBox(height: 16),
          Text(l.yataiQuantity, style: Ty.caption),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final q in _options) ...[
                if (q != _options.first) const SizedBox(width: 10),
                Expanded(
                  child: IbashoButton(
                    key: ValueKey<String>('yatai.qty.$q'),
                    label: '×$q',
                    tone: _qty == q ? ButtonTone.accent : ButtonTone.plain,
                    height: 44,
                    expand: true,
                    cue: null,
                    onPressed: widget.price * q <= widget.coins
                        ? () => setState(() => _qty = q)
                        : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l.yataiTotal(total),
            style: Ty.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(null),
        ),
        IbashoButton(
          key: const ValueKey<String>('yatai.qty.confirm'),
          label: widget.price == 0 ? l.yataiGet : l.yataiBuy,
          tone: ButtonTone.accent,
          onPressed: () => Navigator.of(context).pop(_qty),
        ),
      ],
    );
  }
}

/// La descarga falsa: una barra de bloques que se llena en ~2,5 s mientras la
/// compra de verdad va por su lado. Se cierra sola cuando las dos terminan, y
/// devuelve el error (si lo hubo) a quien la abrio.
class _InstallingDialog extends StatefulWidget {
  const _InstallingDialog({required this.future});

  final Future<void> future;

  @override
  State<_InstallingDialog> createState() => _InstallingDialogState();
}

class _InstallingDialogState extends State<_InstallingDialog>
    with SingleTickerProviderStateMixin {
  static const int _blocks = 14;

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );

  int _filled = 0;

  @override
  void initState() {
    super.initState();
    _progress.addListener(() {
      final next = (_progress.value * _blocks).floor().clamp(0, _blocks);
      if (next != _filled) {
        setState(() => _filled = next);
        AudioService.instance.play(Sfx.tick);
      }
    });
    unawaited(_run());
  }

  Future<void> _run() async {
    Object? error;
    await Future.wait<void>([
      _progress.forward(),
      widget.future.catchError((Object e) => error = e),
    ]);
    if (mounted) Navigator.of(context).pop(error);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return IbashoDialog(
      title: l.yataiInstallingTitle,
      width: 420,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.yataiInstallingBody,
            style: Ty.body.copyWith(color: T.inkSoft),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (var i = 0; i < _blocks; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: i < _filled ? skin.accent : T.hairline,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: const [],
    );
  }
}
