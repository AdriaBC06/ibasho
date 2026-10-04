// Malla — piezas del canal: fichas de jugador, colores, menú, logros,
// historial, resultados y reglas.
// Copyright (C) 2026 Julio Solano
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../audio/audio_service.dart';
import '../../backend/malla.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/social/social_widgets.dart' show CardTama, CountBadge;
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/pressable.dart';
import '../../ui/widgets/slot_tile.dart';
import '../game_stage.dart';
import '../koen/koen_album.dart' show koenFriendName;
import 'malla_store.dart';

// --- Colores ---------------------------------------------------------------------

/// `#rrggbb` → color. Uno roto sale del primero de la paleta.
Color mallaColor(String value) {
  final clean = value.toLowerCase();
  if (!RegExp(r'^#[0-9a-f]{6}$').hasMatch(clean)) return Art.mallaPlayers.first;
  return Color(0xFF000000 | int.parse(clean.substring(1), radix: 16));
}

/// Color → `#rrggbb`, como viaja por la sala.
String mallaHex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Una ficha hexagonal de plástico de un color: la del jugador.
class MallaHexChip extends StatelessWidget {
  const MallaHexChip({super.key, required this.color, this.size = 22});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HexChipPainter(color)),
      );
}

class _HexChipPainter extends CustomPainter {
  _HexChipPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 * .92;
    final c = size.center(Offset.zero);
    final path = Path();
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 180 * (30 + 60 * k);
      final p = c + Offset(r * math.cos(a), r * math.sin(a));
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    paintPlastic(canvas, path, color, edge: math.max(1.0, r * .09), shine: .9);
  }

  @override
  bool shouldRepaint(_HexChipPainter old) => old.color != color;
}

/// Elegir el color propio: las seis fichas de la paleta. La elegida sube y
/// se asienta en un disco con el filo del acento.
class MallaColorPicker extends StatelessWidget {
  const MallaColorPicker({super.key, required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final l = L.of(context)!;
    final side = Layout.of(context).pick(42.0, 48.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < Art.mallaPlayers.length; i++)
          Pressable(
            key: ValueKey<String>('malla.color.$i'),
            semanticLabel: '${l.mallaColor} ${i + 1}',
            onPressed: () => onChanged(i),
            builder: (context, st) {
              final on = i == value;
              return Transform.translate(
                offset: Offset(0, (on ? -3 : -2 * st.hover) + 1.5 * st.press),
                child: SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (on)
                        GlossSurface(
                          radius: side / 2,
                          tint: skin.accentWash,
                          borderColor: skin.accentDeep,
                          borderWidth: 2,
                          child: SizedBox(width: side, height: side),
                        ),
                      MallaHexChip(color: Art.mallaPlayers[i], size: side * .72),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// --- Jugadores ---------------------------------------------------------------------

/// Quién ocupa un asiento: nombre, color y Tama (si lo hay).
@immutable
class MallaSeat {
  const MallaSeat({required this.name, required this.color, this.tama, this.mine = false});

  final String name;
  final Color color;
  final MallaTama? tama;
  final bool mine;
}

/// El Tama de un jugador, pequeño y quieto. Sin Tama, la cara de reserva.
class MallaTamaFace extends StatelessWidget {
  const MallaTamaFace({super.key, required this.tama, required this.size, this.joy = .3});

  final MallaTama? tama;
  final double size;
  final double joy;

  @override
  Widget build(BuildContext context) {
    final t = tama;
    if (t == null) return GlossyFace(joy: joy, size: size);
    return IgnorePointer(
      child: TamaView(
        look: t.look,
        personality: t.personality,
        name: t.name,
        seed: t.name.hashCode ^ size.round(),
        size: size,
        joy: joy,
        interactive: false,
        shadow: false,
      ),
    );
  }
}

/// La ficha de un jugador en partida: su Tama, su color, el nombre y los
/// hexágonos. La de quien juega lleva el lavado del acento y sube un poco;
/// la de quien se ha ido, apagada. [compact] es la de la franja de arriba en
/// vertical.
class MallaPlayerTile extends StatelessWidget {
  const MallaPlayerTile({
    super.key,
    required this.seat,
    required this.score,
    required this.current,
    this.note,
    this.out = false,
    this.compact = false,
  });

  final MallaSeat seat;
  final int score;
  final bool current;
  final String? note;
  final bool out;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return AnimatedOpacity(
      opacity: out ? .45 : 1,
      duration: skin.motion(const Duration(milliseconds: 240)),
      child: AnimatedSlide(
        offset: Offset(0, current ? -.05 : 0),
        duration: skin.motion(const Duration(milliseconds: 260)),
        curve: skin.curve(Curves.easeOutBack),
        child: compact ? _compact(skin) : _row(skin),
      ),
    );
  }

  Widget _row(IbashoSkin skin) => SizedBox(
        height: 52,
        child: GlossSurface(
          radius: 26,
          tint: current ? skin.accentWash : null,
          borderColor: current ? skin.accentDeep : skin.hairline,
          borderWidth: current ? 2 : 1,
          elevation: current ? 1.6 : .8,
          padding: const EdgeInsets.fromLTRB(6, 3, 16, 3),
          child: Row(
            children: [
              SizedBox(width: 46, height: 46, child: MallaTamaFace(tama: seat.tama, size: 46)),
              const SizedBox(width: 6),
              MallaHexChip(color: seat.color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(seat.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.body.copyWith(fontWeight: FontWeight.w600, height: 1.15)),
                    if (note != null)
                      Text(note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(height: 1.1)),
                  ],
                ),
              ),
              Text('$score', style: Ty.numeral(26, color: skin.accentDeep, weight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _compact(IbashoSkin skin) => GlossSurface(
        radius: 18,
        tint: current ? skin.accentWash : null,
        borderColor: current ? skin.accentDeep : skin.hairline,
        borderWidth: current ? 2 : 1,
        elevation: current ? 1.4 : .6,
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(width: 34, height: 34, child: MallaTamaFace(tama: seat.tama, size: 34)),
                Positioned(left: -5, top: -3, child: MallaHexChip(color: seat.color, size: 15)),
              ],
            ),
            Text('$score', style: Ty.numeral(18, color: skin.accentDeep, weight: FontWeight.w700)),
          ],
        ),
      );
}

/// Un sitio de la sala de espera: el Tama, el nombre y el color, o una
/// ranura hundida si aún no ha llegado nadie.
class MallaSeatTile extends StatelessWidget {
  const MallaSeatTile({super.key, required this.seat, required this.width, required this.height, this.tag});

  final MallaSeat? seat;
  final double width;
  final double height;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final s = seat;
    if (s == null) return EmptySlot(width: width, height: height);
    final face = math.max(24.0, math.min(width * .62, height - (tag == null ? 34 : 48)));
    return SlotTile(
      width: width,
      height: height,
      semanticLabel: s.name,
      selected: s.mine,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: Center(child: MallaTamaFace(tama: s.tama, size: face))),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MallaHexChip(color: s.color, size: 14),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(s.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (tag != null) Text(tag!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro),
          ],
        ),
      ),
    );
  }
}

/// Un amigo al que invitar a la sala.
class MallaFriendTile extends ConsumerWidget {
  const MallaFriendTile({super.key, required this.account, required this.width, required this.height, required this.onPressed});

  final String account;
  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = koenFriendName(ref, account);
    return SlotTile(
      key: ValueKey<String>('malla.friend.$account'),
      width: width,
      height: height,
      semanticLabel: name,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Column(
          children: [
            Expanded(child: IgnorePointer(child: CardTama(accountId: account, size: math.max(24, math.min(width * .7, height - 30))))),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(color: Ty.ink)),
          ],
        ),
      ),
    );
  }
}

// --- Menú --------------------------------------------------------------------------

/// Una entrada grande del menú, como las de Tsumiki.
class MallaMenuTile extends StatelessWidget {
  const MallaMenuTile({
    super.key,
    required this.glyph,
    required this.title,
    required this.hint,
    required this.onPressed,
    this.badge = 0,
    this.accent = false,
  });

  final Glyph glyph;
  final String title;
  final String hint;
  final VoidCallback onPressed;
  final int badge;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    final icon = GlyphIcon(glyph, size: tall ? 34 : 46, color: skin.accentDeep, strokeWidth: 2.4);
    final text = Column(
      crossAxisAlignment: tall ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.title.copyWith(color: skin.accentDeep)),
        const SizedBox(height: 4),
        Text(hint,
            maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: tall ? TextAlign.start : TextAlign.center, style: Ty.caption),
      ],
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Pressable(
            semanticLabel: title,
            onPressed: onPressed,
            builder: (context, st) => GlossSurface(
              radius: 28,
              tint: accent ? skin.accentWash : null,
              elevation: 1.6 + st.hover - st.press,
              sink: st.press,
              padding: EdgeInsets.all(tall ? 14 : 18),
              child: tall
                  ? Row(children: [icon, const SizedBox(width: 16), Expanded(child: text)])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [icon, const SizedBox(height: 12), text]),
            ),
          ),
        ),
        if (badge > 0) Positioned(top: -6, right: -6, child: CountBadge(count: badge)),
      ],
    );
  }
}

/// El aviso de una invitación: una pastilla de acento con el Tama de quien
/// invita. Al tocarla se pregunta si se entra.
class MallaInviteNotice extends ConsumerWidget {
  const MallaInviteNotice({super.key, required this.invite, required this.onOpen});

  final MallaInvite invite;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final text = l.mallaInviteFrom(koenFriendName(ref, invite.from));
    return PopIn(
      child: Pressable(
        key: const ValueKey<String>('malla.notice'),
        semanticLabel: text,
        onPressed: onOpen,
        builder: (context, st) => GlossSurface(
          radius: 24,
          tint: skin.accent,
          elevation: 2.4 - st.press,
          sink: st.press,
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 36, height: 36, child: IgnorePointer(child: CardTama(accountId: invite.from, size: 36))),
              const SizedBox(width: 8),
              Flexible(
                child: Text(text,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.body.copyWith(color: T.onAccent, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Text(l.mallaInviteSee, style: Ty.caption.copyWith(color: T.onAccent)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de ajuste de la partida: la etiqueta a la izquierda y el control
/// a la derecha, con el mismo ancho de etiqueta en todas.
class MallaOptionRow extends StatelessWidget {
  const MallaOptionRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tall = Layout.of(context).tall;
    return Row(
      children: [
        SizedBox(
          width: tall ? 64 : 128,
          child: Text(label, maxLines: 2, style: Ty.caption.copyWith(color: Ty.ink, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

/// Un raíl de opciones de la partida.
class MallaRail<V> extends StatelessWidget {
  const MallaRail({super.key, required this.options, required this.value, required this.onChanged, this.id});

  final List<(V, String)> options;
  final V value;
  final ValueChanged<V> onChanged;

  /// Para las claves de los tests: `malla.<id>.<valor>`.
  final String? id;

  @override
  Widget build(BuildContext context) {
    final h = Layout.of(context).pick(42.0, 48.0);
    return SegmentRail(
      height: h,
      children: [
        for (final (v, label) in options)
          SegmentPill(
            key: id == null ? null : ValueKey<String>('malla.$id.$v'),
            label: label,
            height: h,
            selected: v == value,
            onPressed: () => onChanged(v),
          ),
      ],
    );
  }
}

/// Flechas y puntos de página, como en el mostrador del Yatai.
class MallaPager extends StatelessWidget {
  const MallaPager({super.key, required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    final l = L.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconPill(
          key: const ValueKey<String>('malla.page.previous'),
          glyph: Glyph.arrowLeft,
          diameter: layout.pill,
          semanticLabel: l.mallaPagePrevious,
          onPressed: page > 0 ? () => onPage(page - 1) : null,
        ),
        const SizedBox(width: 12),
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
        const SizedBox(width: 12),
        IconPill(
          key: const ValueKey<String>('malla.page.next'),
          glyph: Glyph.arrowRight,
          diameter: layout.pill,
          semanticLabel: l.mallaPageNext,
          onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
        ),
      ],
    );
  }
}

/// Lo que dice la pantalla mientras se juega: de quién es el turno.
class MallaStatusPill extends StatelessWidget {
  const MallaStatusPill({super.key, required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return AnimatedSwitcher(
      duration: skin.motion(const Duration(milliseconds: 240)),
      switchInCurve: skin.curve(Curves.easeOutBack),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween<double>(begin: .8, end: 1).animate(a), child: child),
      ),
      child: GlossSurface(
        key: ValueKey<String>('malla.status.$text.$mine'),
        radius: 18,
        recessed: !mine,
        tint: mine ? skin.accentWash : null,
        borderColor: mine ? skin.accentDeep : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Text(
          text,
          key: const ValueKey<String>('malla.turn'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Ty.body.copyWith(fontWeight: FontWeight.w600, color: mine ? skin.accentDeep : Ty.ink),
        ),
      ),
    );
  }
}

// --- Resultados ------------------------------------------------------------------

/// Los resultados sobre el tablero: quién gana, con su Tama, la cuenta, la
/// serie, las monedas y qué hacer ahora.
class MallaResultsCard extends StatelessWidget {
  const MallaResultsCard({
    super.key,
    required this.title,
    required this.winners,
    required this.score,
    required this.actions,
    this.primary,
    this.series,
    this.coins,
    this.coinsGranted = false,
    this.note,
  });

  final String title;
  final List<MallaSeat> winners;
  final String score;
  final String? series;
  final String? coins;
  final bool coinsGranted;
  final String? note;

  /// Lo de al lado: mirar el tablero y salir.
  final List<Widget> actions;

  /// El botón de acento, el que sigue jugando. En vertical va solo en su
  /// línea, encima de los demás.
  final Widget? primary;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    return PopIn(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tall ? 330 : 460),
        child: GlossSurface(
          key: const ValueKey<String>('malla.results'),
          radius: 28,
          elevation: 2.6,
          padding: EdgeInsets.fromLTRB(22, tall ? 16 : 22, 22, tall ? 16 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final w in winners.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: MallaTamaFace(tama: w.tama, size: tall ? 56 : 72, joy: 1),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, textAlign: TextAlign.center, style: Ty.title.copyWith(color: skin.accentDeep)),
              const SizedBox(height: 4),
              Text(score, textAlign: TextAlign.center, style: Ty.numeral(tall ? 22 : 26, color: Ty.ink, weight: FontWeight.w700)),
              if (series != null) ...[const SizedBox(height: 4), Text(series!, textAlign: TextAlign.center, style: Ty.caption)],
              if (coins != null) ...[const SizedBox(height: 10), CoinLine(text: coins!, granted: coinsGranted)],
              if (note != null) ...[const SizedBox(height: 6), Text(note!, textAlign: TextAlign.center, style: Ty.micro)],
              const SizedBox(height: 14),
              if (tall && primary != null) ...[primary!, const SizedBox(height: 10)],
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    if (tall && i == actions.length - 1) Expanded(child: actions[i]) else actions[i],
                  ],
                  if (!tall && primary != null) ...[const SizedBox(width: 10), primary!],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Logros ----------------------------------------------------------------------

class MallaAchievement {
  const MallaAchievement(this.id, this.medal, this.name, this.description, this.unlocked);

  final String id;

  /// La medalla: bronce, plata u oro según lo que cuesta.
  final ArtIcon medal;
  final String Function(L l) name;
  final String Function(L l) description;
  final bool Function(MallaStats stats) unlocked;
}

final List<MallaAchievement> mallaAchievements = <MallaAchievement>[
  MallaAchievement('first_hex', ArtIcon.medalBronze, (l) => l.mallaAchFirstHex, (l) => l.mallaAchFirstHexDesc,
      (s) => s.hexes >= 1 || s.unlocked.contains('first_hex')),
  MallaAchievement('first_win', ArtIcon.medalBronze, (l) => l.mallaAchFirstWin, (l) => l.mallaAchFirstWinDesc, (s) => s.wins >= 1),
  MallaAchievement('games10', ArtIcon.medalBronze, (l) => l.mallaAchGames10, (l) => l.mallaAchGames10Desc, (s) => s.games >= 10),
  MallaAchievement('draw_game', ArtIcon.medalBronze, (l) => l.mallaAchDrawGame, (l) => l.mallaAchDrawGameDesc, (s) => s.draws >= 1),
  MallaAchievement('second_win', ArtIcon.medalBronze, (l) => l.mallaAchSecondWin, (l) => l.mallaAchSecondWinDesc, (s) => s.secondWins >= 1),
  MallaAchievement('online_win', ArtIcon.medalSilver, (l) => l.mallaAchOnlineWin, (l) => l.mallaAchOnlineWinDesc, (s) => s.onlineWins >= 1),
  MallaAchievement('close_win', ArtIcon.medalSilver, (l) => l.mallaAchCloseWin, (l) => l.mallaAchCloseWinDesc, (s) => s.closeWins >= 1),
  MallaAchievement('margin5', ArtIcon.medalSilver, (l) => l.mallaAchMargin5, (l) => l.mallaAchMargin5Desc, (s) => s.maxMargin >= 5),
  MallaAchievement('big_board', ArtIcon.medalSilver, (l) => l.mallaAchBigBoard, (l) => l.mallaAchBigBoardDesc, (s) => s.fiveWins >= 1),
  MallaAchievement('streak3', ArtIcon.medalSilver, (l) => l.mallaAchStreak3, (l) => l.mallaAchStreak3Desc, (s) => s.bestStreak >= 3),
  MallaAchievement('hexes50', ArtIcon.medalSilver, (l) => l.mallaAchHexes50, (l) => l.mallaAchHexes50Desc, (s) => s.hexes >= 50),
  MallaAchievement('last_touch', ArtIcon.medalSilver, (l) => l.mallaAchLastTouch, (l) => l.mallaAchLastTouchDesc, (s) => s.lastTouchCaptures >= 1),
  MallaAchievement('perfect', ArtIcon.medalGold, (l) => l.mallaAchPerfect, (l) => l.mallaAchPerfectDesc, (s) => s.perfectWins >= 1),
  MallaAchievement('full_table', ArtIcon.medalGold, (l) => l.mallaAchFullTable, (l) => l.mallaAchFullTableDesc, (s) => s.fullTableGames >= 1),
  MallaAchievement('against_all', ArtIcon.medalGold, (l) => l.mallaAchAgainstAll, (l) => l.mallaAchAgainstAllDesc, (s) => s.multi4Wins >= 1),
  MallaAchievement('majority', ArtIcon.medalGold, (l) => l.mallaAchMajority, (l) => l.mallaAchMajorityDesc, (s) => s.majorityWins >= 1),
];

/// La medalla de un logro, o un hueco con candado si aún no se tiene.
class MallaMedal extends StatelessWidget {
  const MallaMedal({super.key, required this.achievement, required this.unlocked, required this.size});

  final MallaAchievement achievement;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (unlocked) return ArtIconView(achievement.medal, size: size);
    return SizedBox(
      width: size * .8,
      height: size * .8,
      child: GlossSurface(
        radius: size * .4,
        recessed: true,
        child: Center(child: GlyphIcon(Glyph.lock, size: size * .34, color: Ty.inkSoft)),
      ),
    );
  }
}

/// Una baldosa de la rejilla de logros: la medalla y el nombre.
class MallaAchievementTile extends StatelessWidget {
  const MallaAchievementTile({
    super.key,
    required this.achievement,
    required this.unlocked,
    required this.selected,
    required this.width,
    required this.height,
    required this.onPressed,
  });

  final MallaAchievement achievement;
  final bool unlocked;
  final bool selected;
  final double width;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return SlotTile(
      key: ValueKey<String>('malla.ach.${achievement.id}'),
      width: width,
      height: height,
      selected: selected,
      semanticLabel: achievement.name(l),
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: MallaMedal(achievement: achievement, unlocked: unlocked, size: math.max(24, math.min(width * .52, height - 44))),
              ),
            ),
            Text(
              achievement.name(l),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: Ty.micro.copyWith(color: unlocked ? Ty.ink : Ty.inkSoft, fontWeight: FontWeight.w600, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Historial -------------------------------------------------------------------

/// Una partida online del historial: cómo acabó, cuándo y quién jugó, con
/// sus Tamas y sus hexágonos.
class MallaRecordTile extends StatelessWidget {
  const MallaRecordTile({super.key, required this.record, this.height = 76});

  final MallaRecord record;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tall = Layout.of(context).tall;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final when = '${DateFormat.MMMd(locale).format(record.at)} · ${DateFormat.Hm(locale).format(record.at)}';
    final (result, good) = switch (record) {
      MallaRecord(end: MallaEnd.left) => (l.mallaHistoryLeft, false),
      MallaRecord(won: true) => (l.mallaHistoryWon, true),
      MallaRecord(draw: true) => (l.mallaHistoryDraw, false),
      _ => (l.mallaHistoryLost, false),
    };
    final face = tall ? 30.0 : 38.0;
    return SizedBox(
      key: ValueKey<String>('malla.record.${record.code}'),
      height: height,
      child: GlossSurface(
        radius: 22,
        elevation: 1,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            SizedBox(
              width: tall ? 92 : 150,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ResultChip(text: result, accent: good),
                  const SizedBox(height: 3),
                  Text('$when · ${record.size}×${record.size}', maxLines: 2, overflow: TextOverflow.ellipsis, style: Ty.micro.copyWith(height: 1.1)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < record.players.length; i++)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                SizedBox(width: face, height: face, child: MallaTamaFace(tama: record.players[i].tama, size: face)),
                                Positioned(left: -4, top: -2, child: MallaHexChip(color: mallaColor(record.players[i].color), size: 13)),
                              ],
                            ),
                            Text(
                              '${record.players[i].score}',
                              style: Ty.numeral(16, color: record.winners.contains(i) ? skin.accentDeep : Ty.inkSoft, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Reglas ----------------------------------------------------------------------

/// Cómo se juega, en un diálogo de tres páginas para que nunca haya que
/// desplazar nada.
Future<void> showMallaRules(BuildContext context) => showIbashoModal<void>(context, (_) => const _RulesDialog());

class _RulesDialog extends StatefulWidget {
  const _RulesDialog();

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final pages = <List<String>>[
      [l.mallaRule1, l.mallaRule2],
      [l.mallaRule5, l.mallaRule6],
      [l.mallaRule3, l.mallaRule4, l.mallaRule7],
      [l.mallaRuleOnline, l.mallaCoinsInfo],
    ];
    return IbashoDialog(
      key: const ValueKey<String>('malla.rules'),
      title: l.mallaRulesTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: Layout.of(context).pick(150.0, 190.0)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in pages[_page]) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 3), child: MallaHexChip(color: skin.accent, size: 14)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(line, style: Ty.body)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Center(child: MallaPager(page: _page, pages: pages.length, onPage: (p) => setState(() => _page = p))),
        ],
      ),
      actions: [
        IbashoButton(
          key: const ValueKey<String>('malla.rules.close'),
          label: l.actionClose,
          expand: Layout.of(context).tall,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
