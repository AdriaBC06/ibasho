// Ibasho — canal de Hatarakitama: el pueblo, la tienda y la lonja.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_channel.dart';

/// Lo que da [b] a nivel [level], en frases cortas. Con [onlyNew], de lo que
/// abre solo lo que llega justo a ese nivel.
List<String> _townEffects(L l, HBuilding b, int level, {bool onlyNew = false}) {
  if (level <= 0) return [l.hatarakiEffectNothing];
  int pct(double v) => (v * 100).round();
  String speed(HSkill s) =>
      l.hatarakiEffectSpeed(hSkillName(l, s), pct(level * hBuildingSpeed));
  String? unlocks() {
    final names = [
      for (final e in hActionGates.entries)
        if (e.value.$1 == b &&
            (onlyNew ? e.value.$2 == level : e.value.$2 <= level))
          hActionName(l, hAction(e.key)!),
    ];
    return names.isEmpty ? null : l.hatarakiEffectUnlocks(names.join(', '));
  }

  return switch (b) {
    HBuilding.workshop => [
      l.hatarakiEffectSpeed(
        l.hatarakiEffectCrafts,
        pct(level * hWorkshopSpeed),
      ),
    ],
    HBuilding.kiln => [
      speed(HSkill.pottery),
      l.hatarakiEffectSoot(pct(.5 + level * hKilnSoot).clamp(0, 100)),
    ],
    HBuilding.dock => [speed(HSkill.fishing)],
    HBuilding.greenhouse => [speed(HSkill.farming)],
    HBuilding.library => [
      l.hatarakiEffectStudy(pct(level * hLibraryStudy)),
      ?unlocks(),
    ],
    HBuilding.tower => [speed(HSkill.magic), ?unlocks()],
    HBuilding.inn => [
      l.hatarakiEffectFood(pct(level * hInnFood)),
      l.hatarakiEffectParty(level >= hInnFourth ? hMaxParty + 1 : hMaxParty),
      if (level >= hTownMaxLevel) l.hatarakiEffectTrips,
    ],
    HBuilding.shop => [l.hatarakiEffectShop(hShopSlots(level))],
    HBuilding.market => [
      l.hatarakiEffectUps(hMarketUpsSeen(level), hMarketUps),
      if (level >= hMarketTomorrow) l.hatarakiEffectTomorrow,
    ],
    HBuilding.board => [
      l.hatarakiEffectOrders(hBoardSlots(level)),
      if (level > 1) l.hatarakiEffectPay(pct((level - 1) * hBoardPay)),
    ],
  };
}

/// Nombre de un cambio de la lonja: «lo de pesca» o la cosa.
String _moveName(L l, HMarketMove m) => m.skill != null
    ? l.hatarakiMarketSkill(hSkillName(l, m.skill!))
    : hItemName(l, m.item!);

/// «+50 %» o «−30 %».
String _pctText(double pct) {
  final n = (pct * 100).round().abs();
  return pct >= 0 ? '+$n %' : '−$n %';
}

// --- Rejilla ------------------------------------------------------------------

/// Los edificios del pueblo o, dentro de la tienda o la lonja, lo que hay.
class _TownGrid extends StatelessWidget {
  const _TownGrid({
    required this.game,
    required this.today,
    required this.selected,
    required this.rooms,
    required this.inside,
    required this.offer,
    required this.order,
    required this.tomorrow,
    required this.tall,
    required this.page,
    required this.onPage,
    required this.onPick,
    required this.onOffer,
    required this.onOrder,
    required this.onBack,
  });

  final HState game;
  final int today;
  final HBuilding selected;

  /// Habitaciones hechas en la posada (con alguna, la posada sale hecha).
  final int rooms;
  final HBuilding? inside;
  final String? offer;

  /// El encargo elegido en el tablón.
  final int order;
  final bool tomorrow;
  final bool tall;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<HBuilding> onPick;
  final ValueChanged<String> onOffer;
  final ValueChanged<int> onOrder;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    if (inside == HBuilding.shop) return _shop(context, l, skin);
    if (inside == HBuilding.market) return _market(context, l);
    if (inside == HBuilding.board) return _board(context, l);
    return GlossSurface(
      radius: 22,
      recessed: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: _TownMap(
                game: game,
                selected: selected,
                rooms: rooms,
                tall: tall,
                onPick: onPick,
              ),
            ),
            // Ir de visita al pueblo de un amigo: abajo en medio, sobre el
            // río, que es lo único que no tapa ningún edificio.
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: Center(
                child: IconPill(
                  key: const ValueKey<String>('hataraki.visit'),
                  glyph: Glyph.friends,
                  diameter: 34,
                  semanticLabel: l.hatarakiVisitFriend,
                  onPressed: () => unawaited(pickHatarakiVisit(context)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, L l, HBuilding b, {Widget? trailing}) =>
      Row(
        children: [
          IconPill(
            key: const ValueKey<String>('hataraki.town.back'),
            glyph: Glyph.arrowLeft,
            diameter: 36,
            semanticLabel: l.hatarakiTabTown,
            cue: null,
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          HatarakiBuildingIcon(b, size: 30),
          const SizedBox(width: 6),
          Expanded(child: Text(l.hatarakiBuildingName(b.name), style: Ty.lead)),
          ?trailing,
        ],
      );

  Widget _shop(BuildContext context, L l, IbashoSkin skin) {
    final offers = game.shop(today);
    return Column(
      children: [
        _header(
          context,
          l,
          HBuilding.shop,
          trailing: Row(
            children: [
              const ArtIconView(ArtIcon.ginmon, size: 22),
              const SizedBox(width: 4),
              Text(
                _compact(game.money),
                style: Ty.numeral(
                  18,
                  color: skin.accentDeep,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _Pager(
            count: offers.length,
            columns: tall ? 3 : 4,
            rows: tall ? 3 : 2,
            page: page,
            onPage: onPage,
            builder: (i, w, h) {
              final o = offers[i];
              final left = game.stockLeft(o, today);
              return SlotTile(
                key: ValueKey<String>('hataraki.offer.${o.item}'),
                width: w,
                height: h,
                selected: o.item == offer,
                semanticLabel: o.plan
                    ? l.hatarakiPlanOf(hItemName(l, o.item))
                    : hItemName(l, o.item),
                onPressed: () => onOffer(o.item),
                child: Opacity(
                  opacity: left > 0 ? 1 : .5,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                    child: Column(
                      children: [
                        Expanded(
                          child: FittedBox(
                            child: o.plan
                                ? HatarakiPlanIcon(o.item, size: 48)
                                : HatarakiItemIcon(o.item, size: 48),
                          ),
                        ),
                        Text(
                          o.plan
                              ? l.hatarakiPlanOf(hItemName(l, o.item))
                              : hItemName(l, o.item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.micro.copyWith(color: Ty.ink),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const ArtIconView(ArtIcon.ginmon, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${o.price}',
                              style: Ty.numeral(
                                14,
                                color: skin.accentDeep,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          left > 0
                              ? l.hatarakiShopLeft(left)
                              : o.plan
                              ? l.hatarakiPlanKnown
                              : l.hatarakiSoldOut,
                          style: Ty.micro,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _board(BuildContext context, L l) {
    final orders = game.orders;
    final left = orders.where((o) => !o.done).length;
    return Column(
      children: [
        _header(
          context,
          l,
          HBuilding.board,
          trailing: Text(l.hatarakiOrdersLeft(left), style: Ty.caption),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _Pager(
            // Caben los seis (el grande y cinco normales) sin pasar página.
            count: orders.length,
            columns: 3,
            rows: 2,
            page: page,
            onPage: onPage,
            builder: (i, w, h) => _OrderTile(
              key: ValueKey<String>('hataraki.order.$i'),
              game: game,
              order: orders[i],
              width: w,
              height: h,
              selected: i == order,
              onPressed: () => onOrder(i),
            ),
          ),
        ),
      ],
    );
  }

  Widget _market(BuildContext context, L l) {
    final moves = game.marketSeen(tomorrow ? today + 1 : today);
    return Column(
      children: [
        _header(
          context,
          l,
          HBuilding.market,
          trailing: Text(
            l.hatarakiMarketWhen(tomorrow ? 'tomorrow' : 'today'),
            style: Ty.caption,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _Pager(
            count: moves.length,
            columns: tall ? 3 : 4,
            rows: tall ? 3 : 2,
            page: page,
            onPage: onPage,
            builder: (i, w, h) {
              final m = moves[i];
              final up = m.pct >= 0;
              return SizedBox(
                key: ValueKey<String>('hataraki.move.$i'),
                width: w,
                height: h,
                child: GlossSurface(
                  radius: T.tileRadius,
                  elevation: .8,
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    children: [
                      Expanded(
                        child: FittedBox(
                          child: m.skill != null
                              ? HatarakiSkillIcon(m.skill!, size: 48)
                              : HatarakiItemIcon(m.item!, size: 48),
                        ),
                      ),
                      Text(
                        _moveName(l, m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.micro.copyWith(color: Ty.ink),
                      ),
                      Text(
                        '${up ? '▲' : '▼'} ${_pctText(m.pct)}',
                        style: Ty.numeral(
                          15,
                          color: up ? T.correct : T.wrong,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// --- Mapa ---------------------------------------------------------------------

/// Dónde va cada edificio en el mapa, por filas (de arriba abajo) y con su
/// sitio de izquierda a derecha (0–1). La última fila es la de la orilla.
const List<List<(HBuilding, double)>> _wideTown = [
  [
    (HBuilding.tower, .11),
    (HBuilding.library, .33),
    (HBuilding.workshop, .6),
    (HBuilding.kiln, .86),
  ],
  [
    (HBuilding.greenhouse, .13),
    (HBuilding.board, .39),
    (HBuilding.shop, .64),
    (HBuilding.market, .875),
  ],
  [(HBuilding.inn, .27), (HBuilding.dock, .72)],
];

const List<List<(HBuilding, double)>> _tallTown = [
  [(HBuilding.tower, .17), (HBuilding.library, .5), (HBuilding.kiln, .83)],
  [
    (HBuilding.workshop, .17),
    (HBuilding.board, .5),
    (HBuilding.greenhouse, .83),
  ],
  [(HBuilding.shop, .27), (HBuilding.market, .73)],
  [(HBuilding.inn, .27), (HBuilding.dock, .73)],
];

/// Un poco de desorden para que no parezca una rejilla (en altos de parcela).
const Map<HBuilding, double> _townNudge = {
  HBuilding.tower: -.04,
  HBuilding.library: .03,
  HBuilding.kiln: -.02,
  HBuilding.workshop: .04,
  HBuilding.greenhouse: -.03,
  HBuilding.shop: .02,
  HBuilding.market: -.04,
};

/// Árboles de relleno: se quedan los que no pisan ningún edificio.
const List<(double, double)> _townTrees = [
  (.03, .08),
  (.22, .05),
  (.47, .03),
  (.72, .06),
  (.97, .1),
  (.02, .4),
  (.26, .34),
  (.52, .3),
  (.76, .36),
  (.98, .42),
  (.05, .72),
  (.5, .66),
  (.95, .7),
  (.5, .8),
  (.07, .84),
  (.93, .84),
  (.14, .64),

  (.4, .9),
  (.6, .9),
  (.02, .9),
];

/// El pueblo pintado: los edificios en sus parcelas, con su nivel a la vista,
/// unidos por caminos y con el río abajo. Tocar uno lo elige.
class _TownMap extends StatelessWidget {
  const _TownMap({
    required this.game,
    required this.selected,
    required this.rooms,
    required this.tall,
    required this.onPick,
    this.visit = false,
  });

  final HState game;
  final HBuilding? selected;
  final int rooms;
  final bool tall;
  final ValueChanged<HBuilding> onPick;

  /// El pueblo de otro: sin avisos de lo que se puede hacer.
  final bool visit;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final rows = tall ? _tallTown : _wideTown;
    final cols = rows.fold(0, (m, r) => math.max(m, r.length));
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final lotW = math.min(
          w / (cols + .35),
          h / (rows.length + .5) * hLotWidth / hLotHeight,
        );
        final lotH = lotW * hLotHeight / hLotWidth;
        final scale = lotW / hLotWidth;
        // El río, bajo la última fila; el muelle se mete en el agua.
        final river = h - lotH * .32;
        final top = lotH * .5;
        final bottom = river - lotH * .6;
        double rowY(int i) => rows.length == 1
            ? top
            : top + (bottom - top) * i / (rows.length - 1);
        final lots = <(HBuilding, Offset)>[
          for (var i = 0; i < rows.length; i++)
            for (final (b, x) in rows[i])
              (
                b,
                Offset(
                  x * w,
                  b == HBuilding.dock
                      ? river - lotH * .34
                      : rowY(i) + (_townNudge[b] ?? 0) * lotH,
                ),
              ),
        ]..sort((a, b) => a.$2.dy.compareTo(b.$2.dy));
        // Una calle delante de cada fila y otra que baja por en medio.
        final front = lotH * .4;
        final roads = <(Offset, Offset)>[
          for (var i = 0; i < rows.length; i++)
            (
              Offset(rows[i].first.$2 * w, rowY(i) + front),
              Offset(rows[i].last.$2 * w, rowY(i) + front),
            ),
          (Offset(w * .5, rowY(0) + front), Offset(w * .5, river)),
        ];
        final trees = [
          for (final (x, y) in _townTrees)
            if (y * h < river - lotH * .15 &&
                lots.every(
                  (e) =>
                      (e.$2.dx - x * w).abs() > lotW * .62 ||
                      (e.$2.dy - y * h).abs() > lotH * .62,
                ) &&
                roads.every(
                  (r) => _offRoad(r, Offset(x * w, y * h), lotW * .2),
                ))
              Offset(x * w, y * h),
        ];
        final label = lotW >= 70;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TownGroundPainter(
                    roads: roads,
                    trees: trees,
                    river: river,
                    scale: scale,
                  ),
                ),
              ),
            ),
            for (final (b, at) in lots)
              Positioned(
                left: at.dx - lotW / 2,
                top: at.dy - lotH / 2,
                width: lotW,
                height: lotH,
                child: _TownLot(
                  key: ValueKey<String>('hataraki.building.${b.name}'),
                  building: b,
                  level: game.townLevel(b),
                  built:
                      game.townLevel(b) > 0 ||
                      (b == HBuilding.inn && rooms > 0),
                  width: lotW,
                  selected: b == selected,
                  label: label,
                  news:
                      !visit &&
                      (game.canBuild(b) ||
                          b == HBuilding.board &&
                              Iterable<int>.generate(
                                game.orders.length,
                              ).any(game.canDeliver)),
                  name: l.hatarakiBuildingName(b.name),
                  skin: skin,
                  onPressed: () => onPick(b),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Si [p] queda a más de [gap] del tramo de calle [r].
bool _offRoad((Offset, Offset) r, Offset p, double gap) {
  final (a, b) = r;
  final ab = b - a;
  final len = ab.distanceSquared;
  final t = len == 0
      ? 0.0
      : (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance > gap;
}

class _TownGroundPainter extends CustomPainter {
  _TownGroundPainter({
    required this.roads,
    required this.trees,
    required this.river,
    required this.scale,
  });

  final List<(Offset, Offset)> roads;
  final List<Offset> trees;
  final double river;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) => paintHatarakiTownGround(
    canvas,
    size,
    roads: roads,
    trees: trees,
    river: river,
    scale: scale,
  );

  @override
  bool shouldRepaint(_TownGroundPainter old) =>
      old.river != river ||
      old.scale != scale ||
      old.roads.length != roads.length ||
      old.trees.length != trees.length ||
      !Iterable.generate(roads.length).every((i) => old.roads[i] == roads[i]);
}

/// Una parcela del mapa: el edificio, un halo si está elegido, un «+» si hay
/// algo que hacer y un cartelito con el nombre y el nivel.
class _TownLot extends StatelessWidget {
  const _TownLot({
    super.key,
    required this.building,
    required this.level,
    required this.built,
    required this.width,
    required this.selected,
    required this.label,
    required this.news,
    required this.name,
    required this.skin,
    required this.onPressed,
  });

  final HBuilding building;
  final int level;
  final bool built;
  final double width;
  final bool selected;
  final bool label;
  final bool news;
  final String name;
  final IbashoSkin skin;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final height = width * hLotHeight / hLotWidth;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (selected)
              Positioned(
                left: width * .04,
                right: width * .04,
                top: height * .66,
                height: height * .34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(
                      Radius.elliptical(width * .46, height * .17),
                    ),
                    color: skin.accent.withValues(alpha: .28),
                    border: Border.all(color: skin.accent, width: 2.4),
                  ),
                ),
              ),
            Positioned.fill(
              child: AnimatedScale(
                scale: selected ? 1.06 : 1,
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.bottomCenter,
                child: HatarakiTownLot(
                  building,
                  level: level,
                  built: built,
                  width: width,
                ),
              ),
            ),
            // El cartelito: nombre (si cabe), nivel y el «+» si hay algo.
            Positioned(
              left: -8,
              right: -8,
              bottom: -height * .1,
              child: Center(
                child: Container(
                  padding: EdgeInsets.fromLTRB(6, 1, news ? 3 : 6, 2),
                  decoration: BoxDecoration(
                    color: T.shellTop.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: selected ? skin.accent : skin.hairline,
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (label)
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Ty.micro.copyWith(color: Ty.ink),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: _Pips(level: level, dot: label ? 5 : 4),
                            ),
                          ],
                        ),
                      ),
                      if (news) ...[
                        const SizedBox(width: 3),
                        GlyphIcon(
                          Glyph.plus,
                          size: label ? 13 : 10,
                          color: skin.accentDeep,
                          strokeWidth: 2.8,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cinco puntitos con el nivel del edificio.
class _Pips extends StatelessWidget {
  const _Pips({required this.level, this.dot = 8});

  final int level;
  final double dot;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < hTownMaxLevel; i++)
          Container(
            width: dot,
            height: dot,
            margin: EdgeInsets.symmetric(horizontal: dot / 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < level ? skin.accent : skin.hairline,
            ),
          ),
      ],
    );
  }
}

// --- Escaparate ---------------------------------------------------------------

/// Un edificio: para qué sirve, lo que da ahora, lo que dará y lo que cuesta.
class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.game,
    required this.building,
    required this.tamas,
    this.visit = false,
  });

  final HState game;
  final HBuilding building;

  /// En el pueblo de otro: lo que tiene, sin lo que costaría subirlo.
  final bool visit;

  /// Para las habitaciones de la posada.
  final List<Tama> tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final b = building;
    final level = game.townLevel(b);
    final cost = game.nextBuildCost(b);
    final construction = game.levelOf(HSkill.construction);
    // Con alguna habitación, la posada ya se ve hecha (como en el mapa).
    final built =
        level > 0 ||
        (b == HBuilding.inn && tamas.any((t) => game.houses.containsKey(t.id)));
    return _Card(
      icon: HatarakiBuildingIcon(b, size: 44, built: built),
      title: l.hatarakiBuildingName(b.name),
      subtitle: level > 0 ? l.hatarakiTownLevel(level) : l.hatarakiUnbuilt,
      children: [
        Text(l.hatarakiBuildingAbout(b.name), style: Ty.caption),
        if (b == HBuilding.inn) ..._roomLines(l),
        if (level > 0) ...[
          _Label(l.hatarakiTownNow),
          for (final e in _townEffects(l, b, level))
            Text(e, style: Ty.caption.copyWith(color: Ty.ink)),
        ],
        if (cost != null && !visit) ...[
          _Label(l.hatarakiTownNext(level + 1)),
          for (final e in _townEffects(l, b, level + 1, onlyNew: true))
            Text(e, style: Ty.caption),
          _Label(l.hatarakiTownCost),
          Row(
            children: [
              const ArtIconView(ArtIcon.ginmon, size: 26),
              const SizedBox(width: 4),
              Text(
                '${_compact(game.money)}/${_compact(cost.money)}',
                style: Ty.numeral(
                  13,
                  weight: FontWeight.w700,
                  color: game.money < cost.money ? T.warn : Ty.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ItemRow(items: cost.items, have: game, counts: true),
          if (construction < cost.construction)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.hatarakiNeedConstruction(cost.construction, construction),
                style: Ty.caption.copyWith(color: T.warn),
              ),
            ),
          _Sources(
            items: [
              for (final e in cost.items.entries)
                if (game.count(e.key) < e.value) e.key,
            ],
          ),
        ],
      ],
    );
  }
}

extension on _BuildingCard {
  /// Las habitaciones de la posada: cuántas hay y lo que cuesta la siguiente.
  List<Widget> _roomLines(L l) {
    final built = tamas.where((t) => game.houses.containsKey(t.id)).length;
    return [
      _Label(l.hatarakiHomes),
      Text(
        l.hatarakiHomesCount(built, tamas.length),
        style: Ty.caption.copyWith(color: Ty.ink),
      ),
      Text(l.hatarakiHomesAbout, style: Ty.caption),
      if (built < tamas.length && !visit) ..._houseCostLines(l, game),
    ];
  }
}

/// Una cosa de la tienda: a cuánto, cuántas quedan y para qué sirve.
class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.game,
    required this.offer,
    required this.left,
  });

  final HState game;
  final HOffer offer;
  final int left;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    if (offer.plan) return _planCard(l);
    final uses = [
      for (final a in hActions)
        if (a.inputs.containsKey(offer.item)) a,
    ];
    return _Card(
      icon: HatarakiItemIcon(offer.item, size: 44),
      title: hItemName(l, offer.item),
      subtitle:
          '×${game.count(offer.item)} · ${left > 0 ? l.hatarakiShopLeft(left) : l.hatarakiSoldOut}',
      children: [
        Text(l.hatarakiShopHint, style: Ty.caption),
        if (uses.isNotEmpty) ...[
          _Label(l.hatarakiUsedIn),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final a in uses.take(6))
                ResultChip(
                  text: hActionName(l, a),
                  icon: HatarakiSkillIcon(a.skill, size: 16),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

extension on _OfferCard {
  /// Un plano: qué mueble deja hacer, en qué oficio y con qué.
  Widget _planCard(L l) {
    final a = hActionById[offer.item];
    return _Card(
      icon: HatarakiPlanIcon(offer.item, size: 44),
      title: l.hatarakiPlanOf(hItemName(l, offer.item)),
      subtitle: left > 0 ? _furnitureInfo(l, offer.item) : l.hatarakiPlanKnown,
      children: [
        Text(l.hatarakiPlanHint, style: Ty.caption),
        if (a != null) ...[
          _Label('${hSkillName(l, a.skill)} · ${l.hatarakiLevel(a.level)}'),
          _ItemRow(items: a.inputs, have: game, counts: true),
        ],
      ],
    );
  }
}

/// La lonja: qué se paga bien y qué no, hoy o mañana.
class _MarketCard extends StatelessWidget {
  const _MarketCard({
    required this.game,
    required this.today,
    required this.tomorrow,
  });

  final HState game;
  final int today;
  final bool tomorrow;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final when = tomorrow ? 'tomorrow' : 'today';
    final moves = game.marketSeen(tomorrow ? today + 1 : today);
    final level = game.townLevel(HBuilding.market);
    return _Card(
      icon: const HatarakiBuildingIcon(HBuilding.market, size: 44),
      title: l.hatarakiBuildingName(HBuilding.market.name),
      subtitle: l.hatarakiTownLevel(level),
      children: [
        _Label(l.hatarakiMarketUp(when)),
        Text(
          [
            for (final m in moves)
              if (m.pct > 0) '${_moveName(l, m)} ${_pctText(m.pct)}',
          ].join(' · '),
          style: Ty.caption.copyWith(color: Ty.ink),
        ),
        _Label(l.hatarakiMarketDown(when)),
        Text(
          [
            for (final m in moves)
              if (m.pct < 0) '${_moveName(l, m)} ${_pctText(m.pct)}',
          ].join(' · '),
          style: Ty.caption.copyWith(color: Ty.ink),
        ),
        const SizedBox(height: 6),
        Text(l.hatarakiMarketHint, style: Ty.micro),
      ],
    );
  }
}
