// Ibasho — canal del Yatai: el puesto de feria, al estilo Canal Tienda Wii.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../audio/audio_service.dart';
import '../../../backend/gacha.dart';
import '../../../games/odori/odori_catalog.dart' show odoriTitles;
import '../../../backend/missions.dart';
import '../../../backend/shop.dart';
import '../../../backend/tama.dart';
import '../../../games/tamakoro/koro_song.dart';
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
import '../../widgets/channel_art.dart';
import '../../widgets/controls.dart';
import '../../widgets/gift_face.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/pedestal.dart';
import '../../widgets/overlays.dart';
import '../../widgets/pressable.dart';
import '../../widgets/slot_tile.dart';
import '../channel_route.dart';
import 'gacha_channel.dart';

/// Las tres secciones, en el mismo orden que en el catalogo.
enum _Tab { games, tamas, gacha }

/// La ilustracion, el nombre y la descripcion de un juego. Crecen con
/// `gameChannelRegistry` en `channel.dart`.
ArtIcon _gameArt(String gameId) => switch (gameId) {
      'tsumiki' => ArtIcon.tsumiki,
      'nihongo' => ArtIcon.nihongo,
      _ => ArtIcon.minesweeper,
    };

String _gameTitle(L l, String gameId) => switch (gameId) {
      'minesweeper' => l.minesweeperTitle,
      'tsumiki' => l.tsumikiTitle,
      'nihongo' => l.nihongoTitle,
      _ => gameId,
    };

/// El nombre, la ilustracion y la descripcion de cualquier articulo: comida,
/// juego o ticket del gachapon.
String itemName(L l, ShopItem it) => it.food != null
    ? foodLabel(l, it.food!)
    : it.ticket != null
        ? ticketName(l, it.ticket!)
        : it.koroTier != null
            ? l.koroShopName
            : it.odoriSong != null
                ? l.yataiOdoriSong(odoriTitles[it.odoriSong]?.$1 ?? it.odoriSong!)
                : _gameTitle(l, it.gameId!);

ArtIcon itemArt(ShopItem it) => it.ticket != null
    ? ticketArt(it.ticket!)
    : it.koroTier != null
        ? ArtIcon.tamakoro
        : it.odoriSong != null
            ? ArtIcon.odori
            : _gameArt(it.gameId!);

String _gameDesc(L l, String gameId) => switch (gameId) {
      'tsumiki' => l.yataiDescTsumiki,
      'nihongo' => l.yataiDescNihongo,
      _ => l.yataiDescGame,
    };

String _coins(BuildContext context, int n) =>
    NumberFormat.decimalPattern(Localizations.localeOf(context).languageCode).format(n);

/// El canal de la tienda.
///
/// Una sola escena, como el Canal Tienda de la Wii: arriba el escaparate, con
/// el articulo elegido flotando sobre su peana bajo un foco, su nombre, el
/// precio en una etiqueta y el boton de comprar; en medio las tres secciones;
/// abajo el mostrador, con los articulos en baldosas por paginas. Comprar
/// pide confirmacion (y cantidad, si es comida) y luego envuelve el regalo o
/// llena la bolsa mientras la compra de verdad viaja al servidor.
class YataiChannel extends ConsumerStatefulWidget {
  const YataiChannel({super.key});

  @override
  ConsumerState<YataiChannel> createState() => _YataiChannelState();
}

class _YataiChannelState extends ConsumerState<YataiChannel> {
  _Tab _tab = _Tab.games;
  String? _selectedId;
  int _page = 0;

  List<ShopItem> _items(_Tab tab) {
    final section = switch (tab) {
      _Tab.games => ShopSection.games,
      _Tab.tamas => ShopSection.tamas,
      _Tab.gacha => ShopSection.gacha,
    };
    // De los huecos de Tamakoro se ve solo el del tramo en el que va la
    // cuenta, y solo si el canal ya ha llegado.
    final koroOpen = ref.read(tamasProvider).tamas.isNotEmpty ||
        ref.read(preferencesProvider).koroOpened;
    final slots = ref.read(koroProvider).slots;
    return shopCatalog
        .where((i) => i.section == section)
        .where((i) =>
            i.koroTier == null ||
            (koroOpen && slots < koroMaxSlots && i.koroTier == koroSlotTier(slots)))
        .toList(growable: false);
  }

  void _setTab(_Tab tab) {
    if (tab == _tab) return;
    AudioService.instance.play(Sfx.tick);
    final items = _items(tab);
    setState(() {
      _tab = tab;
      _page = 0;
      _selectedId = items.isEmpty ? null : items.first.id;
    });
  }

  void _select(ShopItem item) {
    if (item.id == _selectedId) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _selectedId = item.id);
  }

  void _goToPage(int page, int pages) {
    if (page < 0 || page >= pages || page == _page) return;
    AudioService.instance.play(Sfx.tick);
    setState(() => _page = page);
  }

  Future<void> _buy(ShopItem item) async {
    final l = L.of(context)!;
    final shop = ref.read(shopProvider);
    final coins = ref.read(coinsProvider);
    final price = shop.prices[item.id];
    if (price == null) return;

    var qty = 1;
    final ticket = item.ticket;
    if (item.food != null) {
      final picked = await showIbashoModal<int>(
        context,
        (context) => _QuantityDialog(
          title: l.yataiConfirmTitle(foodLabel(l, item.food!)),
          art: CustomPaint(size: const Size.square(64), painter: TamaFoodPainter(item.food!, fill: .44)),
          price: price,
          coins: coins,
          maxQty: maxPurchaseQty,
        ),
      );
      if (picked == null) return;
      qty = picked;
    } else if (ticket != null) {
      final left = ref.read(shopProvider).ticketsLeftThisWeek(ticket);
      if (left <= 0) {
        AudioService.instance.play(Sfx.error);
        showIbashoToast(context, l.gachaErrorWeekly, isError: true);
        return;
      }
      final picked = await showIbashoModal<int>(
        context,
        (context) => _QuantityDialog(
          title: l.yataiConfirmTitle(ticketName(l, ticket)),
          art: ArtIconView(ticketArt(ticket), size: 64),
          price: price,
          coins: coins,
          maxQty: left,
        ),
      );
      if (picked == null) return;
      qty = picked;
    } else {
      final ok = await askConfirmation(
        context,
        title: l.yataiConfirmTitle(itemName(l, item)),
        body: price == 0 ? l.yataiConfirmBodyFree : l.yataiConfirmBodyPrice(price),
        confirmLabel: price == 0 ? l.yataiGet : l.yataiBuy,
        cancelLabel: l.actionCancel,
      );
      if (!ok) return;
    }

    if (!mounted) return;
    final buyFuture = ref.read(shopProvider.notifier).buy(item, qty);
    final error = await showIbashoModal<Object?>(
      context,
      (context) => _PurchaseDialog(future: buyFuture, item: item, qty: qty),
    );
    if (!mounted) return;

    if (error != null) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, _errorMessage(l, error), isError: true);
      return;
    }
    AudioService.instance.play(Sfx.chime);
    unawaited(ref.read(missionsProvider.notifier).mark(MissionEvent.buy));
    if (item.koroTier != null) {
      ref.read(koroProvider.notifier).boughtSlots(ref.read(koroProvider).slots + 1);
      // El siguiente hueco puede ser de otro tramo: se elige el que toque.
      setState(() => _selectedId = null);
    }
    final done = switch (item.section) {
      ShopSection.games when item.koroTier != null => l.koroShopDone,
      ShopSection.games when item.odoriSong != null => l.yataiDoneOdoriSong,
      ShopSection.games => l.yataiDoneGame,
      ShopSection.gacha => l.gachaDoneTickets(qty),
      ShopSection.tamas => l.yataiDoneFood(qty, foodLabel(l, item.food!)),
    };
    showIbashoToast(context, done);
  }

  String _errorMessage(L l, Object error) {
    final failure = error is ShopException ? error.failure : ShopFailure.rejected;
    return switch (failure) {
      ShopFailure.noPrice => l.yataiErrorNoPrice,
      ShopFailure.insufficientCoins => l.yataiErrorInsufficientCoins,
      ShopFailure.foodLocked => l.yataiErrorFoodLocked,
      ShopFailure.weeklyLimit => l.gachaErrorWeekly,
      ShopFailure.alreadyOwned => l.yataiErrorAlreadyOwned,
      ShopFailure.network => l.yataiErrorNetwork,
      ShopFailure.rejected => l.yataiErrorRejected,
    };
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, int pages) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _goToPage(_page + 1, pages);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _goToPage(_page - 1, pages);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final tall = layout.tall;
    final shop = ref.watch(shopProvider);
    final coins = ref.watch(coinsProvider);
    final unlocked = ref.watch(unlockedFoodsProvider);
    final pantry = ref.watch(pantryProvider);
    // `_items` lee los huecos de Tamakoro: si cambian, el mostrador tambien.
    ref.watch(koroProvider.select((k) => k.slots));

    final items = _items(_tab);
    if (_selectedId == null && items.isNotEmpty) _selectedId = items.first.id;
    final selected = items.isEmpty
        ? null
        : items.firstWhere((i) => i.id == _selectedId, orElse: () => items.first);

    final perPage = tall ? 6 : 6;
    final pages = math.max(1, (items.length / perPage).ceil());
    if (_page >= pages) _page = pages - 1;
    final pageItems = items.skip(_page * perPage).take(perPage).toList();

    final showcase = !shop.loaded
            ? Center(child: Text(l.loading, style: Ty.lead))
            : _Showcase(
                item: selected,
                shop: shop,
                coins: coins,
                unlocked: unlocked,
                pantry: pantry,
                onBuy: selected == null ? null : () => unawaited(_buy(selected)),
              );

    final shelf = _Shelf(
            items: pageItems,
            perPage: perPage,
            columns: tall ? 3 : 6,
            selectedId: selected?.id,
            shop: shop,
            unlocked: unlocked,
            pantry: pantry,
            onSelect: _select,
          );

    final pager = pages <= 1
        ? null
        : _Pager(
            page: _page,
            pages: pages,
            onPrevious: () => _goToPage(_page - 1, pages),
            onNext: () => _goToPage(_page + 1, pages),
          );

    return ChannelScaffold(
      title: l.yataiTitle,
      glyph: Glyph.yatai,
      art: ArtIcon.yatai,
      trailing: _BalancePill(coins: coins),
      child: Focus(
        onKeyEvent: (node, event) => _onKey(node, event, pages),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.gutter),
          child: LayoutBuilder(builder: (context, box) {
            if (tall) {
              final top = math.max(210.0, math.min(320.0, box.maxHeight * .44));
              return Column(
                children: [
                  const SizedBox(height: 8),
                  SizedBox(height: top, child: showcase),
                  const SizedBox(height: 10),
                  _Tabs(tab: _tab, onChanged: _setTab),
                  const SizedBox(height: 10),
                  Expanded(
                    child: PageSwipe(
                      onPrevious: () => _goToPage(_page - 1, pages),
                      onNext: () => _goToPage(_page + 1, pages),
                      child: shelf,
                    ),
                  ),
                  if (pager != null) ...[const SizedBox(height: 6), pager],
                  const SizedBox(height: 12),
                ],
              );
            }
            return Column(
              children: [
                const SizedBox(height: 10),
                SizedBox(height: 318, child: showcase),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Spacer(),
                    _Tabs(tab: _tab, onChanged: _setTab),
                    Expanded(
                      child: Align(alignment: Alignment.centerRight, child: pager ?? const SizedBox()),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: PageSwipe(
                    onPrevious: () => _goToPage(_page - 1, pages),
                    onNext: () => _goToPage(_page + 1, pages),
                    child: shelf,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// --- Saldo, en la cabecera --------------------------------------------------

class _BalancePill extends StatelessWidget {
  const _BalancePill({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;
    return GlossSurface(
      key: const ValueKey<String>('yatai.balance'),
      radius: 22,
      elevation: 1,
      padding: EdgeInsets.fromLTRB(6, 5, tall ? 12 : 16, 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtIconView(ArtIcon.coin, size: tall ? 26 : 30),
          const SizedBox(width: 7),
          Text(_coins(context, coins), style: Ty.numeral(tall ? 17 : 20, weight: FontWeight.w700)),
          if (!tall) ...[
            const SizedBox(width: 6),
            Text(l.coinsLabel, style: Ty.caption),
          ],
        ],
      ),
    );
  }
}

// --- Escaparate ---------------------------------------------------------------

/// La peana de cristal con el foco: lo que se enseña flota encima,
/// La etiqueta del precio: una pastilla con la moneda, o una cinta de
/// «gratis».
class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.price, this.large = true});

  final int? price;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final p = price;
    if (p == null) {
      return Text(l.yataiPriceNotAvailable, style: Ty.caption);
    }
    final h = large ? 38.0 : 24.0;
    if (p == 0) {
      return GlossSurface(
        radius: h / 2,
        tint: T.presenceOnline,
        elevation: large ? 1 : .5,
        padding: EdgeInsets.symmetric(horizontal: h * .5, vertical: 0),
        child: SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.yataiPriceFree,
                style: (large ? Ty.lead : Ty.caption).copyWith(color: T.onAccent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }
    return GlossSurface(
      radius: h / 2,
      recessed: true,
      padding: EdgeInsets.fromLTRB(h * .12, 0, h * .42, 0),
      child: SizedBox(
        height: h,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ArtIconView(ArtIcon.coin, size: h * .8),
            SizedBox(width: h * .15),
            Text(_coins(context, p), style: Ty.numeral(h * .5, color: skin.accentDeep, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

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
    final layout = Layout.of(context);
    final tall = layout.tall;
    final it = item;
    if (it == null) return const SizedBox.shrink();

    final locked = it.food != null && !unlocked.contains(it.food);
    final owned = (it.gameId != null && shop.games.containsKey(it.gameId)) ||
        (it.odoriSong != null && shop.hasOdoriSong(it.odoriSong!));
    final price = shop.prices[it.id];
    final name = itemName(l, it);
    final description = it.food != null
        ? l.yataiDescFood
        : it.ticket != null
            ? l.yataiGachaBody
            : it.koroTier != null
                ? l.koroShopDesc(koroMaxSlots)
                : it.odoriSong != null
                    ? l.yataiDescOdoriSong
                    : _gameDesc(l, it.gameId!);

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

    Widget art(double s) => it.food != null
        ? Opacity(
            opacity: locked ? .45 : 1,
            child: CustomPaint(size: Size.square(s), painter: TamaFoodPainter(it.food!, fill: .44)),
          )
        : ArtIconView(itemArt(it), size: s);

    final button = IbashoButton(
      key: const ValueKey<String>('yatai.buy'),
      label: actionLabel,
      glyph: owned ? Glyph.check : (locked ? Glyph.lock : Glyph.gift),
      tone: actionEnabled ? ButtonTone.accent : ButtonTone.plain,
      height: tall ? 50 : 54,
      minWidth: 240,
      expand: tall,
      cue: null,
      onPressed: actionEnabled ? onBuy : null,
    );

    final meta = Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (!owned) _PriceTag(price: price, large: !tall),
        if (it.food != null && !locked)
          Text(l.yataiUnitsOwned(pantry[it.food] ?? 0), style: Ty.caption),
        // De los tickets, lo que de verdad limita no es el precio: es el
        // cupo de la semana.
        if (it.ticket != null)
          Text(l.gachaWeeklyLeft(shop.ticketsLeftThisWeek(it.ticket!)), style: Ty.caption),
        if (locked)
          Row(mainAxisSize: MainAxisSize.min, children: [
            GlyphIcon(Glyph.lock, size: 15, color: Ty.inkSoft),
            const SizedBox(width: 4),
            Text(l.yataiLocked, style: Ty.caption),
          ]),
      ],
    );

    if (tall) {
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                LayoutBuilder(
                  builder: (context, box) {
                    final s = math.min(150.0, box.maxHeight / 1.18);
                    return Pedestal(size: s, child: art(s * .82));
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(name, maxLines: 1, style: Ty.title),
                      ),
                      const SizedBox(height: 4),
                      Text(description, maxLines: 3, overflow: TextOverflow.ellipsis,
                          style: Ty.caption.copyWith(height: 1.3)),
                      const SizedBox(height: 10),
                      meta,
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          button,
        ],
      );
    }

    return Row(
      children: [
        SizedBox(width: 380, child: Center(child: Pedestal(size: 250, child: art(205)))),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.display.copyWith(fontSize: 42)),
              const SizedBox(height: 8),
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: Ty.lead.copyWith(color: Ty.inkSoft, fontWeight: FontWeight.w400)),
              const SizedBox(height: 18),
              meta,
              const SizedBox(height: 26),
              button,
            ],
          ),
        ),
        const SizedBox(width: 30),
      ],
    );
  }
}

// --- Secciones -----------------------------------------------------------------

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onChanged});

  final _Tab tab;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;
    final options = <(_Tab, String, Widget)>[
      (_Tab.games, l.yataiTabGames, const ArtIconView(ArtIcon.minesweeper)),
      (_Tab.tamas, l.yataiTabTamas, const CustomPaint(painter: TamaFoodPainter(TamaFood.cookie, fill: .42))),
      (_Tab.gacha, l.yataiTabGacha, const ArtIconView(ArtIcon.gacha)),
    ];
    // En vertical cada pestaña tiene que llegar a los 48 de un dedo.
    final h = tall ? 56.0 : 52.0;
    return SizedBox(
      key: const ValueKey<String>('yatai.tabs'),
      height: h,
      child: GlossSurface(
        radius: h / 2,
        recessed: true,
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: tall ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final (value, label, icon) in options)
              tall
                  ? Expanded(child: _TabButton(label: label, icon: icon, selected: value == tab, onTap: () => onChanged(value), height: h - 8))
                  : _TabButton(label: label, icon: icon, selected: value == tab, onTap: () => onChanged(value), height: h - 8, width: 150),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.height,
    this.width,
  });

  final String label;
  final Widget icon;
  final bool selected;
  final VoidCallback onTap;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      cue: null,
      semanticLabel: label,
      onPressed: onTap,
      builder: (context, state) {
        final ink = selected ? skin.accentDeep : Color.lerp(Ty.inkSoft, Ty.ink, state.hover)!;
        // Estrecha (un movil pequeño): icono encima y la etiqueta debajo, en
        // pequeño, para que no se corte.
        final content = LayoutBuilder(
          builder: (context, box) => box.maxWidth < 96
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: height * .48, height: height * .48, child: icon),
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.micro.copyWith(fontWeight: FontWeight.w700, color: ink, height: 1.1)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: height * .78, height: height * .78, child: icon),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.body.copyWith(fontWeight: FontWeight.w600, color: ink),
                      ),
                    ),
                  ],
                ),
        );
        return SizedBox(
          width: width,
          height: height,
          child: selected
              ? GlossSurface(
                  radius: height / 2,
                  tint: skin.accentWash,
                  borderColor: skin.accentDeep,
                  borderWidth: 1.6,
                  elevation: 1.2,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: content,
                )
              : Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: content),
        );
      },
    );
  }
}

// --- Mostrador -------------------------------------------------------------------

/// Flechas y puntos de pagina del mostrador.
class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.onPrevious, required this.onNext});

  final int page;
  final int pages;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconPill(
          key: const ValueKey<String>('yatai.page.previous'),
          glyph: Glyph.arrowLeft,
          diameter: layout.pill,
          onPressed: page > 0 ? onPrevious : null,
        ),
        const SizedBox(width: 12),
        Semantics(
          label: l.yataiShelf(page + 1, pages),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pages; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                AnimatedContainer(
                  duration: skin.motion(T.hover),
                  width: i == page ? 22 : 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: i == page ? skin.accent : skin.hairline,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconPill(
          key: const ValueKey<String>('yatai.page.next'),
          glyph: Glyph.arrowRight,
          diameter: layout.pill,
          onPressed: page < pages - 1 ? onNext : null,
        ),
      ],
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.items,
    required this.perPage,
    required this.columns,
    required this.selectedId,
    required this.shop,
    required this.unlocked,
    required this.pantry,
    required this.onSelect,
  });

  final List<ShopItem> items;
  final int perPage;
  final int columns;
  final String? selectedId;
  final ShopState shop;
  final Set<TamaFood> unlocked;
  final Map<TamaFood, int> pantry;
  final ValueChanged<ShopItem> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 14.0;
      final rows = (perPage / columns).ceil();
      final tileW = (box.maxWidth - gap * (columns - 1)) / columns;
      final tileH = math.min((box.maxHeight - gap * (rows - 1)) / rows, tileW * 1.1);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Row(
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  if (r * columns + c < items.length)
                    _ShopTile(
                      key: ValueKey<String>('yatai.item.${items[r * columns + c].id}'),
                      item: items[r * columns + c],
                      width: tileW,
                      height: tileH,
                      selected: items[r * columns + c].id == selectedId,
                      shop: shop,
                      unlocked: unlocked,
                      pantry: pantry,
                      onPressed: () => onSelect(items[r * columns + c]),
                    )
                  else
                    EmptySlot(width: tileW, height: tileH),
                ],
              ],
            ),
          ],
        ],
      );
    });
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
    final skin = IbashoSkin.of(context);
    final locked = item.food != null && !unlocked.contains(item.food);
    final owned = item.gameId != null && shop.games.containsKey(item.gameId);
    final name = itemName(l, item);
    final price = shop.prices[item.id];
    final art = height * .5;

    return SlotTile(
      width: width,
      height: height,
      selected: selected,
      onPressed: onPressed,
      semanticLabel: locked ? '$name · ${l.yataiLocked}' : name,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(6, height * .08, 6, height * .06),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Opacity(
                        opacity: locked ? .35 : 1,
                        child: item.food != null
                            ? CustomPaint(size: Size.square(art), painter: TamaFoodPainter(item.food!, fill: .44))
                            : ArtIconView(itemArt(item), size: art),
                      ),
                    ),
                  ),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Ty.caption.copyWith(fontWeight: FontWeight.w600, color: locked ? Ty.inkSoft : Ty.ink)),
                  const SizedBox(height: 3),
                  if (owned)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      GlyphIcon(Glyph.check, size: 13, color: skin.accentDeep, strokeWidth: 2.4),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(l.yataiInstalled, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Ty.micro.copyWith(color: skin.accentDeep, fontWeight: FontWeight.w600)),
                      ),
                    ])
                  else if (locked)
                    GlyphIcon(Glyph.lock, size: 14, color: Ty.inkSoft)
                  else
                    FittedBox(fit: BoxFit.scaleDown, child: _PriceTag(price: price, large: false)),
                ],
              ),
            ),
          ),
          if (item.food != null && !locked)
            Positioned(
              right: 8,
              top: 8,
              child: _CountBadge(count: pantry[item.food] ?? 0),
            ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 10,
      tint: count > 0 ? skin.accent : null,
      elevation: .5,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      child: Text(
        '×$count',
        style: Ty.micro.copyWith(color: count > 0 ? T.onAccent : Ty.inkSoft, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// El paso de cantidad, para la comida: ×1, ×5 o ×10, con el total.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({
    required this.title,
    required this.art,
    required this.price,
    required this.coins,
    required this.maxQty,
  });

  final String title;

  /// La ilustracion de lo que se compra, a 64 px.
  final Widget art;

  final int price;
  final int coins;

  /// Lo maximo que se puede pedir de una tacada: el tope de compra de la
  /// comida o lo que queda del cupo semanal de un ticket.
  final int maxQty;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final List<int> _options = <int>[
    for (final q in const <int>[1, 5, 10])
      if (q <= widget.maxQty) q,
    if (widget.maxQty < 10 && widget.maxQty > 1 && widget.maxQty != 5) widget.maxQty,
  ]..sort();
  late int _qty = _options.firstWhere((q) => widget.price * q <= widget.coins, orElse: () => 1);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final total = widget.price * _qty;
    final affordable = widget.price * _qty <= widget.coins;

    return IbashoDialog(
      title: widget.title,
      width: 480,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 64, height: 64, child: widget.art),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.price == 0 ? l.yataiConfirmBodyFree : l.yataiConfirmBodyPrice(widget.price),
                  style: Ty.body.copyWith(color: Ty.inkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_options.length > 1) ...[
            Text(l.yataiQuantity, style: Ty.label),
            const SizedBox(height: 8),
          ],
          LayoutBuilder(builder: (context, box) {
            const gap = 10.0;
            final w = (box.maxWidth - gap * (_options.length - 1)) / _options.length;
            return Row(
              children: [
                for (final q in _options) ...[
                  if (q != _options.first) const SizedBox(width: gap),
                  Opacity(
                    opacity: widget.price * q <= widget.coins ? 1 : .45,
                    child: SlotTile(
                      key: ValueKey<String>('yatai.qty.$q'),
                      width: w,
                      height: 74,
                      selected: _qty == q,
                      semanticLabel: '×$q',
                      onPressed: widget.price * q <= widget.coins
                          ? () {
                              AudioService.instance.play(Sfx.tick);
                              setState(() => _qty = q);
                            }
                          : null,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('×$q', style: Ty.numeral(24, weight: FontWeight.w700)),
                            Text('${widget.price * q}', style: Ty.micro),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              const ArtIconView(ArtIcon.coin, size: 26),
              const SizedBox(width: 8),
              Text(l.yataiTotal(total), style: Ty.lead.copyWith(fontWeight: FontWeight.w600)),
            ],
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
          glyph: Glyph.gift,
          tone: ButtonTone.accent,
          onPressed: affordable ? () => Navigator.of(context).pop(_qty) : null,
        ),
      ],
    );
  }
}

/// Mientras se compra: un juego se envuelve delante de ti (la caja aparece,
/// cae la tapa y se ata el lazo) y la comida cae en su bolsa. La barra de
/// progreso se llena en ~2,5 s mientras la compra de verdad va por su lado;
/// se cierra sola cuando las dos terminan y devuelve el error, si lo hubo.
class _PurchaseDialog extends StatefulWidget {
  const _PurchaseDialog({required this.future, required this.item, required this.qty});

  final Future<void> future;
  final ShopItem item;
  final int qty;

  @override
  State<_PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<_PurchaseDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );

  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    _progress.addListener(() {
      // Un tick cada octavo, como los bloques de la Wii.
      final step = (_progress.value * 8).floor();
      if (step != _lastTick) {
        _lastTick = step;
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
    final game = widget.item.gameId != null;
    return IbashoDialog(
      title: game ? l.yataiWrappingTitle : l.yataiPackingTitle,
      width: 440,
      body: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final t = _progress.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 140,
                child: game
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          // El icono del juego se mete en la caja al empezar.
                          if (t < .3)
                            Transform.translate(
                              offset: Offset(0, 60 * Curves.easeIn.transform(t / .3)),
                              child: Opacity(
                                opacity: 1 - t / .3,
                                child: ArtIconView(itemArt(widget.item), size: 80),
                              ),
                            ),
                          SizedBox(
                            width: 150,
                            height: 140,
                            child: GiftFace(open: 1 - Curves.easeInOut.transform(((t - .15) / .75).clamp(0.0, 1.0))),
                          ),
                        ],
                      )
                    : _FoodDrop(
                        food: widget.item.food,
                        ticket: widget.item.ticket,
                        qty: widget.qty,
                        t: t,
                      ),
              ),
              const SizedBox(height: 6),
              Text(game ? l.yataiWrappingBody : l.yataiPackingBody,
                  textAlign: TextAlign.center, style: Ty.body.copyWith(color: Ty.inkSoft)),
              const SizedBox(height: 16),
              _ProgressBar(value: t, accent: skin.accent),
            ],
          );
        },
      ),
      actions: const [],
    );
  }
}

/// Las chuches cayendo una a una en la bolsa de papel.
class _FoodDrop extends StatelessWidget {
  const _FoodDrop({required this.food, this.ticket, required this.qty, required this.t});

  final TamaFood? food;

  /// Un ticket del gachapon cae a la bolsa igual que la comida.
  final TicketKind? ticket;
  final int qty;
  final double t;

  @override
  Widget build(BuildContext context) {
    final n = math.min(qty, 5);
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        for (var i = 0; i < n; i++)
          Builder(builder: (context) {
            final start = i / (n + 1) * .8;
            final k = Curves.bounceOut.transform(((t - start) / .3).clamp(0.0, 1.0));
            final dx = (i - (n - 1) / 2) * 14.0;
            return Positioned(
              bottom: 30 + (1 - k) * 90 + (i.isOdd ? 6 : 0),
              left: null,
              child: Transform.translate(
                offset: Offset(dx, 0),
                child: Opacity(
                  opacity: t > start ? 1 : 0,
                  child: food != null
                      ? CustomPaint(size: const Size.square(56), painter: TamaFoodPainter(food!, fill: .44))
                      : ArtIconView(ticketArt(ticket!), size: 56),
                ),
              ),
            );
          }),
        const Positioned(bottom: 0, child: _Bag()),
      ],
    );
  }
}

class _Bag extends StatelessWidget {
  const _Bag();

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(130, 62), painter: _BagPainter());
}

class _BagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(16),
      bottomRight: const Radius.circular(16),
    );
    paintPlastic(canvas, Path()..addRRect(r), Art.woodLight, edge: 2);
    // Doblez de la boca y una estrella de pegatina.
    canvas.drawLine(Offset(8, size.height * .22), Offset(size.width - 8, size.height * .22),
        Paint()
          ..strokeWidth = 1.6
          ..color = Art.deep(Art.woodLight, .25));
    paintTwinkle(canvas, Offset(size.width / 2, size.height * .6), 10, Art.awningRed);
  }

  @override
  bool shouldRepaint(_BagPainter old) => false;
}

/// Barra de progreso de cristal: rail hundido y un relleno del acento con
/// rayas que corren, como la descarga del Canal Tienda.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        child: GlossSurface(
          radius: 11,
          recessed: true,
          padding: const EdgeInsets.all(3),
          child: CustomPaint(painter: _ProgressPainter(value, accent), size: Size.infinite),
        ),
      );
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.value, this.accent);

  final double value;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * value.clamp(0.0, 1.0);
    if (w < 1) return;
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, math.max(w, size.height), size.height), Radius.circular(size.height / 2));
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(accent, T.shellTop, .35)!, Color.lerp(accent, T.dusk, .12)!],
        ).createShader(r.outerRect),
    );
    final stripe = Paint()..color = T.glintSoft;
    final shift = value * 120;
    for (var x = -size.height * 2 + shift % 16; x < w; x += 16) {
      canvas.drawPath(
        Path()
          ..moveTo(x, size.height)
          ..lineTo(x + 7, 0)
          ..lineTo(x + 14, 0)
          ..lineTo(x + 7, size.height)
          ..close(),
        stripe,
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height * .45), Paint()..color = T.glintMid);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ProgressPainter old) => old.value != value || old.accent != accent;
}
