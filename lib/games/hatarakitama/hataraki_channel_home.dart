// Ibasho — canal de Hatarakitama: las casas de los Tamas y sus muebles.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_channel.dart';

/// «rústico · 2×1 · comodidad 2».
String _furnitureInfo(L l, String id) {
  final f = hFurniture[id]!;
  return l.hatarakiFurnitureInfo(
    l.hatarakiStyleName(f.style.name),
    f.w,
    f.h,
    f.comfort,
  );
}

/// Lo que hace falta para las cuentas de comodidad de [tama].
HTama _homeTama(Tama tama) => HTama(tama.id, tama.personality, 0);

/// Una fila de vuelta atrás con su dibujo y su título.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.icon,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final Widget icon;
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return Row(
      children: [
        IconPill(
          key: const ValueKey<String>('hataraki.home.back'),
          glyph: Glyph.arrowLeft,
          diameter: 36,
          semanticLabel: l.hatarakiTabTown,
          cue: null,
          onPressed: onBack,
        ),
        const SizedBox(width: 10),
        icon,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Ty.lead,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

// --- Las casas ------------------------------------------------------------------

/// Los Tamas de la cuenta, cada uno con su casa (o sin ella).
class _HomesGrid extends StatelessWidget {
  const _HomesGrid({
    required this.game,
    required this.tamas,
    required this.selected,
    required this.tall,
    required this.page,
    required this.onPage,
    required this.onPick,
    required this.onBack,
  });

  final HState game;
  final List<Tama> tamas;
  final String? selected;
  final bool tall;
  final int page;
  final ValueChanged<int> onPage;
  final ValueChanged<String> onPick;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final built = tamas.where((t) => game.houses.containsKey(t.id)).length;
    return Column(
      children: [
        _HomeHeader(
          icon: const HatarakiBuildingIcon(HBuilding.inn, size: 30),
          title: l.hatarakiHomes,
          onBack: onBack,
          trailing: Text(
            l.hatarakiHomesCount(built, tamas.length),
            style: Ty.caption,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: tamas.isEmpty
              ? _Notice(text: l.hatarakiNoTamas)
              : _Pager(
                  count: tamas.length,
                  columns: tall ? 3 : 5,
                  rows: tall ? 3 : 2,
                  page: page,
                  onPage: onPage,
                  builder: (i, w, h) {
                    final t = tamas[i];
                    final comfort = game.comfortOf(_homeTama(t));
                    return SlotTile(
                      key: ValueKey<String>('hataraki.home.${t.id}'),
                      width: w,
                      height: h,
                      selected: t.id == selected,
                      semanticLabel: t.name,
                      onPressed: () => onPick(t.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                        child: Column(
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: comfort == null ? .45 : 1,
                                      child: FittedBox(
                                        child: HatarakiHomeIcon(
                                          size: 56,
                                          built: comfort != null,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    bottom: 0,
                                    width: w * .42,
                                    height: w * .42,
                                    child: CustomPaint(
                                      painter: TamaPainter(look: t.look),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.caption.copyWith(color: Ty.ink),
                            ),
                            Text(
                              comfort == null
                                  ? l.hatarakiNoHouse
                                  : l.hatarakiComfort(comfort.percent),
                              maxLines: 1,
                              style: Ty.micro.copyWith(
                                color: comfort == null ? null : skin.accentDeep,
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

/// Lo que cuesta la siguiente casa: ginmon, piezas y construcción.
List<Widget> _houseCostLines(L l, HState game) {
  final cost = game.houseCost;
  final construction = game.levelOf(HSkill.construction);
  return [
    _Label(l.hatarakiHouseCost),
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
  ];
}

/// Las partes de la comodidad de una casa, en líneas.
List<Widget> _comfortLines(L l, HComfort c, Tama tama) {
  int pct(double v) => (v * 100).round();
  final fav = hFavouriteStyle[tama.personality]!;
  return [
    _Bar(value: c.value),
    const SizedBox(height: 4),
    Text(l.hatarakiComfortPieces(c.points), style: Ty.caption),
    Text(l.hatarakiComfortMatch(pct(c.match)), style: Ty.caption),
    Text(
      l.hatarakiComfortLiked(l.hatarakiStyleName(fav.name), pct(c.liked)),
      style: Ty.caption,
    ),
    const SizedBox(height: 4),
    Text(
      l.hatarakiRestMood(pct(hRestMood(c.value))),
      style: Ty.micro.copyWith(color: Ty.ink),
    ),
  ];
}

/// La casa de un Tama: su comodidad o, sin casa, lo que cuesta.
class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.game, required this.tama});

  final HState game;
  final Tama tama;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final comfort = game.comfortOf(_homeTama(tama));
    final fav = hFavouriteStyle[tama.personality]!;
    return _Card(
      icon: SizedBox.square(
        dimension: 44,
        child: CustomPaint(painter: TamaPainter(look: tama.look)),
      ),
      title: tama.name,
      subtitle: comfort == null
          ? l.hatarakiNoHouse
          : l.hatarakiComfort(comfort.percent),
      children: [
        Text(
          l.hatarakiLikesStyle(l.hatarakiStyleName(fav.name)),
          style: Ty.caption.copyWith(color: Ty.ink),
        ),
        const SizedBox(height: 4),
        if (comfort != null)
          ..._comfortLines(l, comfort, tama)
        else ...[
          Text(l.hatarakiHomesAbout, style: Ty.caption),
          ..._houseCostLines(l, game),
        ],
      ],
    );
  }
}

// --- La habitación ------------------------------------------------------------------

/// La habitación de un Tama, con la rejilla para poner muebles y, debajo,
/// los muebles del almacén.
class _RoomView extends StatelessWidget {
  const _RoomView({
    required this.game,
    required this.tama,
    required this.clock,
    required this.piece,
    required this.placed,
    required this.onCell,
    required this.onPiece,
    required this.onBack,
  });

  final HState game;
  final Tama tama;
  final ValueListenable<double> clock;

  /// El mueble del almacén que se va a poner.
  final String? piece;

  /// El mueble puesto que está elegido.
  final int? placed;
  final void Function(int x, int y) onCell;
  final ValueChanged<String> onPiece;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final house = game.houses[tama.id]!;
    final comfort = hComfort(house, tama.personality);
    final owned = [
      for (final f in hFurnitureList)
        if (game.count(f.id) > 0) f.id,
    ];
    return Column(
      children: [
        _HomeHeader(
          icon: SizedBox.square(
            dimension: 30,
            child: CustomPaint(painter: TamaPainter(look: tama.look)),
          ),
          title: tama.name,
          onBack: onBack,
          trailing: Text(
            l.hatarakiComfort(comfort.percent),
            style: Ty.numeral(
              15,
              color: skin.accentDeep,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              final (floor, cell) = hRoomLayout(size);
              final spot = _tamaSpot(house);
              return GestureDetector(
                key: const ValueKey<String>('hataraki.room'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final p = d.localPosition - floor.topLeft;
                  final x = (p.dx / cell).floor(), y = (p.dy / cell).floor();
                  if (x >= 0 && y >= 0 && x < hRoomSize && y < hRoomSize) {
                    onCell(x, y);
                  }
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: HatarakiRoomPainter(
                          house,
                          selected: placed,
                          accent: skin.accent,
                          grid: piece != null || placed != null,
                        ),
                      ),
                    ),
                    // El Tama, en su casa, en una casilla libre.
                    if (spot != null)
                      Positioned(
                        left: floor.left + (spot.$1 - .15) * cell,
                        top: floor.top + (spot.$2 - .45) * cell,
                        width: cell * 1.3,
                        height: cell * 1.3,
                        child: IgnorePointer(
                          child: _WorkingTama(
                            tama: tama,
                            skill: null,
                            clock: clock,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 66,
          child: owned.isEmpty
              ? Center(
                  child: Text(
                    l.hatarakiNoFurniture,
                    textAlign: TextAlign.center,
                    style: Ty.micro,
                  ),
                )
              : ListView.separated(
                  key: const ValueKey<String>('hataraki.room.stock'),
                  scrollDirection: Axis.horizontal,
                  itemCount: owned.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final id = owned[i];
                    return SlotTile(
                      key: ValueKey<String>('hataraki.piece.$id'),
                      width: 62,
                      height: 62,
                      selected: id == piece,
                      semanticLabel: hItemName(l, id),
                      onPressed: () => onPiece(id),
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(5),
                            child: HatarakiItemIcon(id, size: 52),
                          ),
                          Positioned(
                            right: 6,
                            top: 3,
                            child: Text(
                              '×${game.count(id)}',
                              style: Ty.numeral(
                                12,
                                color: skin.accentDeep,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Una casilla libre para el Tama: abajo, hacia el centro.
  static (int, int)? _tamaSpot(HHouse house) {
    for (var y = hRoomSize - 1; y >= 0; y--) {
      for (final x in const [2, 3, 1, 4, 0, 5]) {
        if (house.at(x, y) == null) return (x, y);
      }
    }
    return null;
  }
}

/// Lo elegido en la habitación: un mueble puesto, uno por poner o, si no,
/// la comodidad de la casa.
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.game,
    required this.tama,
    required this.piece,
    required this.placed,
  });

  final HState game;
  final Tama tama;
  final String? piece;
  final int? placed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final house = game.houses[tama.id]!;
    final id = placed != null && placed! < house.items.length
        ? house.items[placed!].id
        : piece;
    if (id != null) {
      return _Card(
        icon: HatarakiItemIcon(id, size: 44),
        title: hItemName(l, id),
        subtitle: _furnitureInfo(l, id),
        children: [
          Text(
            placed != null ? l.hatarakiMoveHint : l.hatarakiPlaceHint,
            style: Ty.caption.copyWith(color: Ty.ink),
          ),
          const SizedBox(height: 4),
          Text(l.hatarakiFurnitureUse, style: Ty.micro),
        ],
      );
    }
    final comfort = hComfort(house, tama.personality);
    final fav = hFavouriteStyle[tama.personality]!;
    return _Card(
      icon: const HatarakiHomeIcon(size: 44),
      title: l.hatarakiComfort(comfort.percent),
      subtitle: l.hatarakiLikesStyle(l.hatarakiStyleName(fav.name)),
      children: [
        Text(l.hatarakiRoomHint, style: Ty.caption.copyWith(color: Ty.ink)),
        const SizedBox(height: 6),
        ..._comfortLines(l, comfort, tama),
      ],
    );
  }
}
