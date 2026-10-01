// Ibasho — canal de Hatarakitama: visitar el pueblo de un amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_channel.dart';

/// Abre el pueblo de [accountId] para mirarlo.
void openHatarakiVisit(BuildContext context, String accountId) {
  pushChannelPage<void>(
    context,
    (_) => HatarakiVisitScreen(accountId: accountId),
  );
}

/// Elige a qué amigo visitar y abre su pueblo.
Future<void> pickHatarakiVisit(BuildContext context) async {
  final account = await showIbashoModal<String>(
    context,
    (_) => const _VisitPicker(),
  );
  if (account != null && context.mounted) {
    openHatarakiVisit(context, account);
  }
}

/// La lista de amigos para ir de visita.
class _VisitPicker extends ConsumerWidget {
  const _VisitPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final friends = ref.watch(friendsProvider.select((f) => f.friends));
    return IbashoDialog(
      title: l.hatarakiVisitPick,
      width: 440,
      body: friends.isEmpty
          ? Text(l.hatarakiVisitNoFriends, style: Ty.body)
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in friends)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _VisitFriend(accountId: f.accountId),
                      ),
                  ],
                ),
              ),
            ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _VisitFriend extends ConsumerWidget {
  const _VisitFriend({required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(cardOfProvider(accountId)).valueOrNull;
    return SlotTile(
      key: ValueKey<String>('hataraki.visit.$accountId'),
      width: double.infinity,
      height: 58,
      semanticLabel: card?.displayName ?? '…',
      onPressed: () => Navigator.of(context).pop(accountId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            CardTama(accountId: accountId, size: 44, card: card),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                card?.displayName ?? '…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Ty.lead,
              ),
            ),
            GlyphIcon(Glyph.arrowRight, size: 18, color: Ty.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// El pueblo de otra cuenta, solo para mirar: sus edificios en el mapa, sus
/// Tamas (qué hacen y sus habitaciones), sus oficios y su riqueza. Se lee
/// una vez al entrar; no se queda escuchando.
class HatarakiVisitScreen extends ConsumerStatefulWidget {
  const HatarakiVisitScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<HatarakiVisitScreen> createState() =>
      _HatarakiVisitScreenState();
}

class _HatarakiVisitScreenState extends ConsumerState<HatarakiVisitScreen>
    with SingleTickerProviderStateMixin {
  HBuilding? _building;
  String? _tamaId;
  bool _inRoom = false;

  late final Ticker _anim;
  final ValueNotifier<double> _clock = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _anim = createTicker((e) => _clock.value = e.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _anim.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _pickBuilding(HBuilding b) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _building = b == _building ? null : b;
      _tamaId = null;
      _inRoom = false;
    });
  }

  void _pickTama(String id) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _tamaId = id == _tamaId ? null : id;
      _building = null;
      _inRoom = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final own = ref.watch(sessionProvider.select((s) => s.accountId));
    final card = ref.watch(cardOfProvider(widget.accountId)).valueOrNull;
    final name = widget.accountId == own
        ? ref.watch(profileProvider.select((p) => p.profile?.displayName)) ??
              '…'
        : card?.displayName ?? '…';
    final visit = ref.watch(hatarakiVisitProvider(widget.accountId));
    final layout = Layout.of(context);
    return ChannelScaffold(
      title: l.hatarakiVisitTitle(name),
      glyph: Glyph.house,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: visit.when(
          loading: () => _Notice(text: l.loading),
          error: (_, _) => _Notice(text: l.hatarakiVisitFailed),
          data: (v) => v == null
              ? _Notice(text: l.hatarakiVisitNone)
              : layout.tall
              ? _tallLayout(v)
              : _wideLayout(v),
        ),
      ),
    );
  }

  Tama? _tama(HatarakiVisit v) =>
      v.tamas.where((t) => t.id == _tamaId).firstOrNull;

  /// El mapa o, si se ha entrado, la habitación del Tama elegido.
  Widget _scene(HatarakiVisit v, {required bool tall}) {
    final tama = _tama(v);
    if (_inRoom && tama != null && v.game.houses.containsKey(tama.id)) {
      return _VisitRoom(
        game: v.game,
        tama: tama,
        clock: _clock,
        onBack: () => setState(() => _inRoom = false),
      );
    }
    return GlossSurface(
      radius: 22,
      recessed: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _TownMap(
          game: v.game,
          selected: _building,
          rooms: v.tamas.where((t) => v.game.houses.containsKey(t.id)).length,
          tall: tall,
          visit: true,
          onPick: _pickBuilding,
        ),
      ),
    );
  }

  /// Lo elegido: un edificio, un Tama o, si no, el resumen del pueblo.
  Widget _card(HatarakiVisit v) {
    final tama = _tama(v);
    if (tama != null) {
      return _VisitTamaCard(
        game: v.game,
        tama: tama,
        clock: _clock,
        inRoom: _inRoom,
        onRoom: () => setState(() => _inRoom = !_inRoom),
      );
    }
    if (_building != null) {
      return _BuildingCard(
        game: v.game,
        building: _building!,
        tamas: v.tamas,
        visit: true,
      );
    }
    return _VisitSummary(game: v.game, tamas: v.tamas);
  }

  Widget _strip(HatarakiVisit v, double size) => SizedBox(
    height: size,
    child: v.tamas.isEmpty
        ? _Notice(text: l10n.hatarakiVisitNoTamas)
        : ListView.separated(
            key: const ValueKey<String>('hataraki.visit.tamas'),
            scrollDirection: Axis.horizontal,
            itemCount: v.tamas.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final t = v.tamas[i];
              return SlotTile(
                key: ValueKey<String>('hataraki.visit.tama.${t.id}'),
                width: size,
                height: size,
                selected: t.id == _tamaId,
                semanticLabel: t.name,
                onPressed: () => _pickTama(t.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                  child: Column(
                    children: [
                      Expanded(
                        child: _WorkingTama(
                          tama: t,
                          skill: _skillOf(v.game, t.id),
                          clock: _clock,
                        ),
                      ),
                      Text(
                        t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.micro.copyWith(color: Ty.ink),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );

  L get l10n => L.of(context)!;

  Widget _wideLayout(HatarakiVisit v) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _card(v)),
              const SizedBox(height: 12),
              _strip(v, 86),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: _scene(v, tall: false)),
      ],
    ),
  );

  Widget _tallLayout(HatarakiVisit v) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 11, child: _scene(v, tall: true)),
        const SizedBox(height: 10),
        _strip(v, 78),
        const SizedBox(height: 10),
        Expanded(flex: 7, child: _card(v)),
      ],
    ),
  );
}

/// El oficio en el que está un Tama ahora (según lo último que guardó su
/// dueña), o `null` si descansa.
HSkill? _skillOf(HState game, String tamaId) {
  final w = game.workers.where((w) => w.tamaId == tamaId).firstOrNull;
  return w == null ? null : hAction(w.actionId)?.skill;
}

/// Lo que hacía un Tama la última vez que se guardó la partida.
String _doingOf(L l, HState game, String tamaId) {
  final w = game.workers.where((w) => w.tamaId == tamaId).firstOrNull;
  if (w != null) {
    final action = hAction(w.actionId)!;
    return l.hatarakiVisitWorking(hActionName(l, action));
  }
  final trip = game.expeditions
      .where((e) => e.tamaIds.contains(tamaId))
      .firstOrNull;
  if (trip != null) return l.hatarakiVisitTrip(hZoneName(l, trip.zone));
  return l.hatarakiVisitResting;
}

/// El pueblo de un vistazo: su riqueza, su nivel y sus mejores oficios.
class _VisitSummary extends StatelessWidget {
  const _VisitSummary({required this.game, required this.tamas});

  final HState game;
  final List<Tama> tamas;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final best = [...HSkill.values.where((s) => game.levelOf(s) > 0)]
      ..sort((a, b) => game.levelOf(b).compareTo(game.levelOf(a)));
    final built = HBuilding.values.where((b) => game.townLevel(b) > 0).length;
    Widget stat(String label, Widget value) => Expanded(
      child: Column(
        children: [
          value,
          Text(label, style: Ty.micro, textAlign: TextAlign.center),
        ],
      ),
    );
    return _Card(
      icon: const HatarakiSkillIcon(HSkill.construction, size: 44),
      title: l.hatarakiVisitAbout,
      subtitle: l.hatarakiVisitHint,
      children: [
        Row(
          children: [
            stat(
              l.hatarakiVisitWealth,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ArtIconView(ArtIcon.ginmon, size: 20),
                  const SizedBox(width: 3),
                  Text(
                    _compact(game.earned),
                    style: Ty.numeral(
                      18,
                      color: skin.accentDeep,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            stat(
              l.hatarakiTotalLevel,
              Text(
                '${game.totalLevel}',
                style: Ty.numeral(18, weight: FontWeight.w700),
              ),
            ),
            stat(
              l.hatarakiVisitBuildings,
              Text(
                '$built/${HBuilding.values.length}',
                style: Ty.numeral(18, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
        if (best.isNotEmpty) ...[
          _Label(l.hatarakiVisitSkills),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in best.take(8))
                ResultChip(
                  text: '${hSkillName(l, s)} ${game.levelOf(s)}',
                  icon: HatarakiSkillIcon(s, size: 16),
                ),
            ],
          ),
        ],
        _Label(l.hatarakiHomes),
        Text(
          l.hatarakiHomesCount(
            tamas.where((t) => game.houses.containsKey(t.id)).length,
            tamas.length,
          ),
          style: Ty.caption.copyWith(color: Ty.ink),
        ),
      ],
    );
  }
}

/// Un Tama del pueblo visitado: qué hace, en qué es bueno y su habitación.
class _VisitTamaCard extends StatelessWidget {
  const _VisitTamaCard({
    required this.game,
    required this.tama,
    required this.clock,
    required this.inRoom,
    required this.onRoom,
  });

  final HState game;
  final Tama tama;
  final ValueListenable<double> clock;
  final bool inRoom;
  final VoidCallback onRoom;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final house = game.houses[tama.id];
    final likes = hAffinities[tama.personality] ?? const <HSkill>[];
    return _Card(
      icon: SizedBox.square(
        dimension: 48,
        child: _WorkingTama(
          tama: tama,
          skill: _skillOf(game, tama.id),
          clock: clock,
        ),
      ),
      title: tama.name,
      subtitle: personalityLabel(l, tama.personality),
      children: [
        Text(
          _doingOf(l, game, tama.id),
          style: Ty.caption.copyWith(color: Ty.ink),
        ),
        if (likes.isNotEmpty) ...[
          _Label(l.hatarakiVisitLikes),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in likes)
                ResultChip(
                  text: hSkillName(l, s),
                  icon: HatarakiSkillIcon(s, size: 16),
                ),
            ],
          ),
        ],
        _Label(l.hatarakiHomes),
        if (house == null)
          Text(l.hatarakiVisitNoRoom, style: Ty.caption)
        else ...[
          Text(
            l.hatarakiComfort(hComfort(house, tama.personality).percent),
            style: Ty.caption.copyWith(color: Ty.ink),
          ),
          const SizedBox(height: 8),
          IbashoButton(
            key: const ValueKey<String>('hataraki.visit.room'),
            label: inRoom ? l.hatarakiVisitBackToTown : l.hatarakiVisitRoom,
            glyph: inRoom ? Glyph.arrowLeft : Glyph.house,
            tone: inRoom ? ButtonTone.plain : ButtonTone.accent,
            expand: true,
            onPressed: onRoom,
          ),
        ],
      ],
    );
  }
}

/// La habitación de un Tama visitado: solo mirar.
class _VisitRoom extends StatelessWidget {
  const _VisitRoom({
    required this.game,
    required this.tama,
    required this.clock,
    required this.onBack,
  });

  final HState game;
  final Tama tama;
  final ValueListenable<double> clock;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final house = game.houses[tama.id]!;
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
            L
                .of(context)!
                .hatarakiComfort(hComfort(house, tama.personality).percent),
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
              final (floor, cell) = hRoomLayout(
                Size(box.maxWidth, box.maxHeight),
              );
              final spot = _RoomView._tamaSpot(house);
              return Stack(
                key: const ValueKey<String>('hataraki.visit.roomView'),
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: HatarakiRoomPainter(house, accent: skin.accent),
                    ),
                  ),
                  if (spot != null)
                    Positioned(
                      left: floor.left + (spot.$1 - .15) * cell,
                      top: floor.top + (spot.$2 - .45) * cell,
                      width: cell * 1.3,
                      height: cell * 1.3,
                      child: _WorkingTama(
                        tama: tama,
                        skill: null,
                        clock: clock,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
