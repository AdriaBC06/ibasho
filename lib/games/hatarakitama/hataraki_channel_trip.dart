// Ibasho — canal de Hatarakitama: expediciones con mapa.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_channel.dart';

/// Lo que dice el globo al pasar una casilla (`fail` si no se pasó un
/// peligro).
String _nodeWhat(HNodeEvent e) => e.failed ? 'fail' : e.kind.name;

/// La casilla tal como se ve: con niebla sale como `fog`.
String _nodeKindName(HMapNode n, {required bool revealed}) =>
    n.fog && !revealed ? 'fog' : n.kind.name;

// --- Rejilla de sitios ----------------------------------------------------------

class _ZoneGrid extends StatelessWidget {
  const _ZoneGrid({
    required this.game,
    required this.page,
    required this.onPage,
    required this.selected,
    required this.tall,
    required this.onPick,
  });

  final HState game;
  final int page;
  final ValueChanged<int> onPage;
  final String selected;
  final bool tall;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final level = game.levelOf(HSkill.expedition);
    return _Pager(
      count: hZones.length,
      columns: tall ? 2 : 4,
      rows: tall ? 4 : 2,
      page: page,
      onPage: onPage,
      builder: (i, w, h) {
        final z = hZones[i];
        final open = level >= z.level;
        final trip = game.tripTo(z.id);
        return SlotTile(
          key: ValueKey<String>('hataraki.zone.${z.id}'),
          width: w,
          height: h,
          selected: z.id == selected,
          semanticLabel: hZoneName(l, z.id),
          onPressed: () => onPick(z.id),
          child: _Badged(
            count: trip?.tamaIds.length ?? 0,
            child: Opacity(
              opacity: open ? 1 : .55,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  children: [
                    Expanded(
                      child: FittedBox(child: HatarakiZoneIcon(z.id, size: 48)),
                    ),
                    Text(
                      hZoneName(l, z.id),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.caption.copyWith(color: Ty.ink),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GlyphIcon(
                          open ? Glyph.clock : Glyph.lock,
                          size: 12,
                          color: Ty.inkSoft,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          trip != null
                              ? l.hatarakiTripStep(trip.done, trip.route.length)
                              : open
                              ? l.hatarakiTripTime(z.minutes)
                              : l.hatarakiLevel(z.level),
                          style: Ty.micro,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- El mapa ------------------------------------------------------------------

/// El mapa de hoy de un sitio (o el del viaje en marcha), con la ruta. Se
/// toca una casilla para pasar por ella.
class _ZoneMap extends StatelessWidget {
  const _ZoneMap({
    required this.game,
    required this.map,
    required this.route,
    required this.revealed,
    required this.trip,
    required this.tamas,
    required this.clock,
    required this.onNode,
    required this.onBack,
  });

  final HState game;
  final HZoneMap map;
  final List<int> route;
  final bool revealed;
  final HExpedition? trip;
  final List<Tama> tamas;
  final ValueListenable<double> clock;
  final void Function(HMapNode node)? onNode;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final fog = revealed
        ? 0
        : map.columns.expand((c) => c).where((n) => n.fog).length;
    return Column(
      children: [
        Row(
          children: [
            IconPill(
              key: const ValueKey<String>('hataraki.map.back'),
              glyph: Glyph.arrowLeft,
              diameter: 36,
              semanticLabel: l.hatarakiTabExpedition,
              cue: null,
              onPressed: onBack,
            ),
            const SizedBox(width: 10),
            HatarakiZoneIcon(map.zone, size: 30),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hZoneName(l, map.zone),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.lead,
                  ),
                  Text(
                    trip != null
                        ? l.hatarakiTripStep(trip!.done, trip!.route.length)
                        : '${l.hatarakiMapToday} · ${fog == 0 ? l.hatarakiMapClear : l.hatarakiMapFog(fog)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GlossSurface(
            radius: 22,
            recessed: true,
            child: _MapBoard(
              game: game,
              map: map,
              route: route,
              revealed: revealed,
              trip: trip,
              tamas: tamas,
              clock: clock,
              onNode: onNode,
            ),
          ),
        ),
      ],
    );
  }
}

class _MapBoard extends StatelessWidget {
  const _MapBoard({
    required this.game,
    required this.map,
    required this.route,
    required this.revealed,
    required this.trip,
    required this.tamas,
    required this.clock,
    required this.onNode,
  });

  final HState game;
  final HZoneMap map;
  final List<int> route;
  final bool revealed;
  final HExpedition? trip;
  final List<Tama> tamas;
  final ValueListenable<double> clock;
  final void Function(HMapNode node)? onNode;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final cols = map.columns.length;
        final colW = box.maxWidth / cols;
        final rowH = box.maxHeight / hMapRows;
        final size = math.min(56.0, math.min(colW * .72, rowH * .66));
        Offset at(int col, int row) =>
            Offset(colW * (col + .5), rowH * (row + .5));
        final trip = this.trip;
        final links = <(Offset, Offset, bool)>[
          for (final column in map.columns.take(cols - 1))
            for (final a in column)
              for (final b in map.columns[a.col + 1])
                if (a.leadsTo(b))
                  (
                    at(a.col, a.row),
                    at(b.col, b.row),
                    route[a.col] == a.row && route[b.col] == b.row,
                  ),
        ];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RoutePainter(
                  links,
                  base: skin.hairline,
                  accent: skin.accent,
                ),
              ),
            ),
            for (final column in map.columns)
              for (final n in column)
                Positioned(
                  left: at(n.col, n.row).dx - size / 2,
                  top: at(n.col, n.row).dy - size / 2,
                  width: size,
                  height: size,
                  child: _MapNode(
                    node: n,
                    zone: map.zone,
                    size: size,
                    onRoute: route[n.col] == n.row,
                    revealed: revealed || (trip != null && n.col < trip.done),
                    log: trip != null && n.col < trip.done
                        ? trip.log[n.col]
                        : null,
                    failed:
                        trip != null &&
                        n.col < trip.done &&
                        trip.fails.contains(n.col),
                    label: l.hatarakiNodeKind(
                      _nodeKindName(n, revealed: revealed),
                    ),
                    onPressed: onNode == null ? null : () => onNode!(n),
                  ),
                ),
            // El grupo, de camino a la casilla que toca.
            if (trip != null)
              ValueListenableBuilder<double>(
                valueListenable: clock,
                builder: (context, _, _) {
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final i = math.min(trip.done, trip.route.length - 1);
                  final from = i == 0 ? trip.startedAt : trip.at[i - 1];
                  final t = ((now - from) / math.max(1, trip.at[i] - from))
                      .clamp(0.0, 1.0);
                  final a = i == 0
                      ? Offset(colW * .1, at(0, trip.route[0]).dy)
                      : at(i - 1, trip.route[i - 1]);
                  final b = at(i, trip.route[i]);
                  final p = Offset.lerp(a, b, t)!;
                  final lead = tamas
                      .where((x) => x.id == trip.tamaIds.firstOrNull)
                      .firstOrNull;
                  const d = 34.0;
                  return Positioned(
                    left: p.dx - d / 2,
                    top: p.dy - size / 2 - d + 6,
                    width: d,
                    height: d,
                    child: IgnorePointer(
                      child: lead == null
                          ? const SizedBox.shrink()
                          : CustomPaint(
                              painter: TamaPainter(
                                look: lead.look,
                                pose: TamaPose(
                                  hop: 3 * math.sin(now / 160).abs(),
                                  joy: .8,
                                ),
                              ),
                            ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.links, {required this.base, required this.accent});

  final List<(Offset, Offset, bool)> links;
  final Color base;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final faint = Paint()
      ..color = base
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final bold = Paint()
      ..color = accent
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final (a, b, on) in links) {
      if (!on) canvas.drawLine(a, b, faint);
    }
    for (final (a, b, on) in links) {
      if (on) canvas.drawLine(a, b, bold);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.links.length != links.length ||
      old.accent != accent ||
      !Iterable.generate(links.length).every((i) => old.links[i] == links[i]);
}

/// Una casilla del mapa: resaltada si está en la ruta y, ya pasada, con lo
/// que salió en ella.
class _MapNode extends StatelessWidget {
  const _MapNode({
    required this.node,
    required this.zone,
    required this.size,
    required this.onRoute,
    required this.revealed,
    required this.log,
    required this.failed,
    required this.label,
    required this.onPressed,
  });

  final HMapNode node;
  final String zone;
  final double size;
  final bool onRoute;
  final bool revealed;
  final Map<String, int>? log;
  final bool failed;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final got = log?.keys.where((k) => k != 'prize').firstOrNull;
    return Pressable(
      key: ValueKey<String>('hataraki.node.${node.col}.${node.row}'),
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Opacity(
        opacity: onRoute ? 1 : .5,
        child: Transform.scale(
          scale: 1 - .06 * state.press,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (onRoute)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.accent, width: 3),
                    ),
                  ),
                ),
              HatarakiNodeIcon(
                zone,
                node.kind,
                size: size,
                fog: node.fog && !revealed,
              ),
              if (log != null)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: T.shellTop,
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: log!.containsKey('prize')
                          ? const ArtIconView(ArtIcon.ticketGachaken, size: 20)
                          : got != null
                          ? HatarakiItemIcon(got, size: 20)
                          : GlyphIcon(
                              failed ? Glyph.cross : Glyph.check,
                              size: 14,
                              color: failed ? T.wrong : T.correct,
                              strokeWidth: 2.6,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Preparar el viaje ---------------------------------------------------------

/// Lo elegido para salir, con lo que falta calculado.
class _TripDraft {
  const _TripDraft({
    required this.plan,
    required this.party,
    required this.hParty,
    required this.foods,
    required this.supplies,
    required this.runes,
    required this.revealed,
    required this.problem,
  });

  final HTripPlan? plan;
  final List<String> party;
  final List<HTama> hParty;
  final List<String> foods;
  final List<String> supplies;
  final List<String> runes;
  final bool revealed;
  final String? problem;
}

/// Un hueco que se va cambiando al tocarlo (comida, poción, runa) o un
/// servicio que se pone y se quita.
class _PlanChip extends StatelessWidget {
  const _PlanChip({
    super.key,
    required this.text,
    required this.onPressed,
    this.item,
    this.on = false,
    this.warn = false,
  });

  final String text;
  final String? item;
  final bool on;
  final bool warn;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: text,
      builder: (context, state) => GlossSurface(
        radius: 16,
        sink: state.press,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item != null) ...[
              HatarakiItemIcon(item!, size: 26),
              const SizedBox(width: 4),
            ] else if (on) ...[
              GlyphIcon(
                Glyph.check,
                size: 14,
                color: skin.accentDeep,
                strokeWidth: 2.6,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.caption.copyWith(
                  color: warn
                      ? T.warn
                      : on
                      ? skin.accentDeep
                      : Ty.ink,
                  fontWeight: on ? FontWeight.w700 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.game,
    required this.zone,
    required this.draft,
    required this.today,
    required this.tamas,
    required this.porter,
    required this.cart,
    required this.onAdd,
    required this.onRemove,
    required this.onFood,
    required this.onSupply,
    required this.onRune,
    required this.onService,
  });

  final HState game;
  final HZone zone;
  final _TripDraft draft;
  final int today;
  final List<Tama> tamas;
  final bool porter;
  final bool cart;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;
  final VoidCallback? onFood;
  final VoidCallback? onSupply;
  final VoidCallback? onRune;
  final ValueChanged<String> onService;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final open = game.levelOf(HSkill.expedition) >= zone.level;
    final plan = draft.plan;
    final party = draft.party;
    final power = plan == null
        ? game.partyPower(draft.hParty, zone.id)
        : game.tripPower(plan, draft.hParty);
    final success = (HState.successFor(zone, power) * 100).round();
    final map = hZoneMap(zone.id, today);
    final route = plan?.route ?? map.defaultRoute;
    final nodes = map.nodesOf(route);
    final speed =
        (cart ? 1 - hCartTime : 1) *
        (hItem(plan?.supply ?? '')?.effect == 'haste' ? 1 - hHasteTime : 1);
    final minutes = (map.minutesOf(route) * speed).round();
    // Los peligros que se ven y no se pasan con esta fuerza.
    final dangers = nodes
        .where(
          (n) =>
              n.kind == HNodeKind.danger &&
              (!n.fog || draft.revealed) &&
              n.threat > power,
        )
        .length;
    final kitPower = game.kit.values
        .where((item) => game.count(item) > 0)
        .fold(0, (sum, item) => sum + (hItem(item)?.power ?? 0));
    final units = plan == null || party.isEmpty
        ? 0
        : game.foodUnits(plan, party.length, today);
    final food = plan?.food;
    return _Card(
      icon: HatarakiZoneIcon(zone.id, size: 40),
      title: hZoneName(l, zone.id),
      subtitle: open
          ? '${l.hatarakiTripTime(minutes)} · ${party.isEmpty ? l.hatarakiStrength(power, zone.difficulty) : l.hatarakiSuccess(success)}'
          : l.hatarakiNeedSkillLevel(
              hSkillName(l, HSkill.expedition),
              zone.level,
              game.levelOf(HSkill.expedition),
            ),
      children: [
        _Bar(
          value: power / zone.difficulty,
          color: power >= zone.difficulty ? T.correct : null,
        ),
        const SizedBox(height: 4),
        Text(
          dangers > 0
              ? '${l.hatarakiStrength(power, zone.difficulty)} · ${l.hatarakiRouteDangers(dangers)}'
              : l.hatarakiStrength(power, zone.difficulty),
          style: Ty.micro.copyWith(color: dangers > 0 ? T.warn : null),
        ),
        _Label(l.hatarakiRoute),
        Row(
          children: [
            for (final n in nodes)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: HatarakiNodeIcon(
                  zone.id,
                  n.kind,
                  size: 26,
                  fog: n.fog && !draft.revealed,
                ),
              ),
          ],
        ),
        _Label(l.hatarakiParty),
        Row(
          children: [
            for (var i = 0; i < game.maxParty; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              if (i < party.length)
                Pressable(
                  onPressed: () => onRemove(party[i]),
                  semanticLabel: tamas
                      .where((t) => t.id == party[i])
                      .firstOrNull
                      ?.name,
                  builder: (context, state) => SizedBox.square(
                    dimension: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: GlossSurface(
                            radius: 14,
                            sink: state.press,
                            child: CustomPaint(
                              painter: TamaPainter(
                                look: tamas
                                    .firstWhere((t) => t.id == party[i])
                                    .look,
                              ),
                            ),
                          ),
                        ),
                        // Se saca del grupo tocándolo: la cruz lo dice.
                        Positioned(
                          right: -4,
                          top: -4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: T.shellTop,
                              shape: BoxShape.circle,
                              border: Border.all(color: skin.hairline),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: GlyphIcon(
                                Glyph.cross,
                                size: 10,
                                color: Ty.inkSoft,
                                strokeWidth: 2.4,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Pressable(
                  key: ValueKey<String>('hataraki.party.add.$i'),
                  onPressed: i == party.length ? onAdd : null,
                  semanticLabel: l.hatarakiAddTama,
                  builder: (context, state) => SizedBox.square(
                    dimension: 48,
                    child: GlossSurface(
                      radius: 14,
                      recessed: true,
                      child: i == party.length
                          ? Center(
                              child: GlyphIcon(
                                Glyph.plus,
                                size: 20,
                                color: skin.accentDeep,
                                strokeWidth: 2.4,
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ],
        ),
        _Label(l.hatarakiFood),
        if (food == null)
          Text(l.hatarakiNoFood, style: Ty.caption.copyWith(color: T.warn))
        else
          Row(
            children: [
              Flexible(
                child: _PlanChip(
                  key: const ValueKey<String>('hataraki.food'),
                  item: food,
                  text: l.hatarakiFoodUnits(units, hItemName(l, food)),
                  warn: game.count(food) < units,
                  onPressed: onFood,
                ),
              ),
            ],
          ),
        // Poción o mapa y runa: se gastan al salir.
        if (draft.supplies.isNotEmpty || draft.runes.isNotEmpty) ...[
          _Label('${l.hatarakiSupply} · ${l.hatarakiRune}'),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (draft.supplies.isNotEmpty)
                _PlanChip(
                  key: const ValueKey<String>('hataraki.supply'),
                  item: plan?.supply,
                  text: plan?.supply == null
                      ? '${l.hatarakiSupply}: ${l.hatarakiNone}'
                      : hItemName(l, plan!.supply!),
                  on: plan?.supply != null,
                  onPressed: onSupply,
                ),
              if (draft.runes.isNotEmpty)
                _PlanChip(
                  key: const ValueKey<String>('hataraki.rune'),
                  item: plan?.rune,
                  text: plan?.rune == null
                      ? '${l.hatarakiRune}: ${l.hatarakiNone}'
                      : hItemName(l, plan!.rune!),
                  on: plan?.rune != null,
                  onPressed: onRune,
                ),
            ],
          ),
        ],
        _Label(l.hatarakiServices),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _PlanChip(
              key: const ValueKey<String>('hataraki.service.guide'),
              text: game.guided(zone.id, today)
                  ? l.hatarakiGuided
                  : '${l.hatarakiService('guide')} · ${hGuidePrice(zone)}',
              on: game.guided(zone.id, today),
              warn:
                  !game.guided(zone.id, today) &&
                  game.money < hGuidePrice(zone),
              onPressed: () => onService('guide'),
            ),
            _PlanChip(
              key: const ValueKey<String>('hataraki.service.porter'),
              text: '${l.hatarakiService('porter')} · ${hPorterPrice(zone)}',
              on: porter,
              onPressed: () => onService('porter'),
            ),
            _PlanChip(
              key: const ValueKey<String>('hataraki.service.cart'),
              text: '${l.hatarakiService('cart')} · ${hCartPrice(zone)}',
              on: cart,
              onPressed: () => onService('cart'),
            ),
          ],
        ),
        // El equipo, en una línea: lo que suma y desde dónde se cambia.
        _Label(l.hatarakiKit),
        Row(
          children: [
            for (final item in game.kit.values)
              if (game.count(item) > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _Labelled(
                    label: hItemName(l, item),
                    child: HatarakiItemIcon(item, size: 26),
                  ),
                ),
            Flexible(
              child: Text(
                kitPower > 0 ? l.hatarakiPower(kitPower) : l.hatarakiKitNone,
                maxLines: 2,
                style: Ty.micro,
              ),
            ),
          ],
        ),
        _Label(l.hatarakiLoot),
        _ItemRow(
          items: {for (final loot in zone.loot) loot.item: loot.max},
          size: 26,
        ),
        // Sin grupo aún, la probabilidad del sitio con éxito completo.
        _TreasureLine(
          chance:
              zone.prizeChance *
              (party.isEmpty ? 1 : HState.successFor(zone, power)),
        ),
      ],
    );
  }
}

// --- De viaje -------------------------------------------------------------------

class _TripCard extends StatelessWidget {
  const _TripCard({required this.expedition, required this.tamas});

  final HExpedition expedition;
  final List<Tama> tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final total = expedition.endsAt - expedition.startedAt;
    final left = Duration(milliseconds: math.max(0, expedition.endsAt - now));
    final zone = hZoneById[expedition.zone]!;
    final brought = <String, int>{};
    for (final got in expedition.log) {
      for (final e in got.entries) {
        if (e.key != 'prize') brought[e.key] = (brought[e.key] ?? 0) + e.value;
      }
    }
    final steps = expedition.route.length;
    return _Card(
      icon: HatarakiZoneIcon(zone.id, size: 40),
      title: hZoneName(l, zone.id),
      subtitle: steps == 0
          ? l.hatarakiBackIn(hDuration(left))
          : '${l.hatarakiTripStep(expedition.done, steps)} · ${l.hatarakiBackIn(hDuration(left))}',
      children: [
        _Bar(value: total <= 0 ? 1 : 1 - left.inMilliseconds / total),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final id in expedition.tamaIds)
              if (tamas.where((t) => t.id == id).firstOrNull case final tama?)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox.square(
                    dimension: 48,
                    child: CustomPaint(
                      painter: TamaPainter(
                        look: tama.look,
                        pose: const TamaPose(hop: 4, joy: .8),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        if (steps > 0) ...[
          _Label(l.hatarakiTripSoFar),
          if (brought.isEmpty)
            Text(l.hatarakiTripNothing, style: Ty.caption)
          else
            _ItemRow(items: brought, size: 26),
        ] else ...[
          _Label(l.hatarakiLoot),
          _ItemRow(
            items: {for (final loot in zone.loot) loot.item: loot.max},
            size: 26,
          ),
        ],
        _TreasureLine(
          chance:
              zone.prizeChance *
              HState.successFor(zone, expedition.power) *
              expedition.luck,
        ),
      ],
    );
  }
}
