// Ibasho — Tama Kōen: el álbum de recuerdos y el resumen al entrar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../audio/audio_service.dart';
import '../../backend/backdrops.dart';
import '../../backend/koen.dart';
import '../../backend/koen_bonds.dart';
import '../../backend/koen_rewards.dart';
import '../../backend/tama.dart' show TamaFood;
import '../../l10n/gen/app_localizations.dart';
import '../../state/koen.dart';
import '../../state/people.dart' show cardOfProvider;
import '../../state/providers.dart' show koenProvider;
import '../../theme/type.dart';
import '../../ui/tama/tama_food.dart';
import '../../ui/tama/tama_text.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/channel_art.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/prize_view.dart';
import 'koen_art.dart';
import 'koen_mood.dart';

/// Una postal del álbum: el parque pintado con la estación y la luz del
/// recuerdo, acercado a su zona, con la cara que ponían. Sin sacar, una
/// silueta gris.
class KoenPostcard extends StatelessWidget {
  const KoenPostcard({super.key, required this.memory, required this.unlocked, this.season});

  final KoenMemory memory;
  final bool unlocked;

  /// La estación que se pinta si el recuerdo no tiene una suya.
  final KoenSeason? season;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: CustomPaint(
      painter: _PostcardPainter(memory, unlocked, memory.season ?? season ?? KoenSeason.spring),
      child: const SizedBox.expand(),
    ),
  );
}

class _PostcardPainter extends CustomPainter {
  _PostcardPainter(this.memory, this.unlocked, this.season);

  final KoenMemory memory;
  final bool unlocked;
  final KoenSeason season;

  static final ValueNotifier<double> _still = ValueNotifier<double>(0);
  static final KoenSceneFx _fx = KoenSceneFx();

  @override
  void paint(Canvas canvas, Size size) {
    // El parque entero mide lo de la escena (1.05 de alto por 1 de ancho
    // en el móvil); la postal enseña un trozo, acercado a la zona.
    final focus = memory.focus;
    final zoom = focus == null ? 1.0 : 2.1;
    final scene = Size(size.width * zoom, size.width * zoom / 1.3);
    final at = focus == null ? const Offset(.5, .6) : koenZoneAt[focus]! + const Offset(0, -.08);
    canvas.save();
    if (!unlocked) {
      canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = const ColorFilter.matrix(_grey));
    }
    final dx = (size.width / 2 - at.dx * scene.width).clamp(size.width - scene.width, 0.0);
    final dy = (size.height / 2 - at.dy * scene.height).clamp(size.height - scene.height, 0.0);
    canvas.translate(dx, dy);
    for (final layer in KoenLayer.values) {
      KoenScenePainter(
        layer: layer,
        season: season,
        daylight: memory.daylight,
        time: _still,
        fx: _fx,
        reducedMotion: true,
      ).paint(canvas, scene);
    }
    canvas.translate(-dx, -dy);
    if (unlocked) {
      final mood = KoenMood.values.byName(memory.mood);
      final b = size.shortestSide * .46;
      canvas.save();
      canvas.translate(size.width - b * 1.08, size.height * .06);
      KoenBubblePainter(mood: mood, tint: const Color(0xFFFFC7D8), age: 1, life: 9, tailRight: false)
          .paint(canvas, Size(b, b * .86));
      canvas.restore();
    } else {
      canvas.restore();
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x66FFFFFF));
      final tp = TextPainter(
        text: TextSpan(
          text: '?',
          style: TextStyle(fontSize: size.height * .42, fontWeight: FontWeight.w800, color: const Color(0xAA6E6878)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      tp.dispose();
    }
    canvas.restore();
  }

  static const List<double> _grey = [
    .25, .6, .15, 0, 20, //
    .25, .6, .15, 0, 20,
    .25, .6, .15, 0, 20,
    0, 0, 0, 1, 0,
  ];

  @override
  bool shouldRepaint(_PostcardPainter old) =>
      old.memory != memory || old.unlocked != unlocked || old.season != season;
}

String _dayLabel(BuildContext context, int day) {
  final date = DateTime.fromMillisecondsSinceEpoch(day * 86400000, isUtc: true);
  return DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(date);
}

/// El álbum: las 25 postales, las que han salido con su día.
class KoenAlbumDialog extends ConsumerWidget {
  const KoenAlbumDialog({super.key, required this.season});

  final KoenSeason season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final album = ref.watch(koenProvider.select((k) => k.album));
    return IbashoDialog(
      title: '${l.koenAlbumTitle} · ${album.length}/${KoenMemory.values.length}',
      width: 620,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.koenAlbumHint, style: Ty.caption),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth > 480 ? 4 : 3;
                  final w = (box.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: [
                      for (final m in KoenMemory.values)
                        SizedBox(
                          width: w,
                          child: Semantics(
                            label: album.containsKey(m) ? l.koenMemory(m.name) : l.koenAlbumLocked,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                AspectRatio(
                                  aspectRatio: 1.3,
                                  child: KoenPostcard(memory: m, unlocked: album.containsKey(m), season: season),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  album.containsKey(m) ? l.koenMemory(m.name) : l.koenAlbumLocked,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Ty.micro.copyWith(color: album.containsKey(m) ? Ty.ink : Ty.inkSoft),
                                ),
                                if (album[m] case final day?)
                                  Text(_dayLabel(context, day), style: Ty.micro.copyWith(fontSize: 10)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionClose,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// «Mientras no estabas»: lo que ha traído el parque desde la última vez.
class KoenSummaryDialog extends StatelessWidget {
  const KoenSummaryDialog({super.key, required this.summary, required this.season});

  final KoenSummary summary;
  final KoenSeason season;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final s = summary;
    return IbashoDialog(
      title: l.koenAwayTitle,
      width: 480,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.koenAwayMeets(s.meets), style: Ty.body),
              if (s.petted.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(l.koenAwayPetted(s.petted.join(', '), s.petted.length), style: Ty.caption),
              ],
              if (s.coins > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const ArtIconView(ArtIcon.coin, size: 30),
                    const SizedBox(width: 8),
                    Text(l.gameCoinsWon(s.coins), style: Ty.label),
                  ],
                ),
              ],
              if (s.food case final food?) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CustomPaint(painter: _FoodPainter(food)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.koenAwayGift(foodLabel(l, food)), style: Ty.body)),
                  ],
                ),
              ],
              if (s.ticket) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const ArtIconView(ArtIcon.ticketGachaken, size: 30),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.koenAwayTicket, style: Ty.body)),
                  ],
                ),
              ],
              if (s.bondUps.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(l.koenAwayBonds(s.bondUps.length), style: Ty.label),
                const SizedBox(height: 6),
                for (final up in s.bondUps) _BondUpRow(up: up),
              ],
              for (final up in s.friendUps) ...[
                const SizedBox(height: 10),
                _FriendUpRow(up: up),
              ],
              for (final key in s.prizes) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    GachaPrizeView(key, size: 44),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        backdropByKey(key) != null
                            ? l.koenPrizeBackdrop(l.backdropName(key))
                            : l.koenPrizeHat(l.prizeName(key)),
                        style: Ty.body,
                      ),
                    ),
                  ],
                ),
              ],
              if (s.memories.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(l.koenAwayMemories(s.memories.length), style: Ty.label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in s.memories)
                      SizedBox(
                        width: 128,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 1.3,
                              child: KoenPostcard(memory: m, unlocked: true, season: season),
                            ),
                            const SizedBox(height: 3),
                            Text(l.koenMemory(m.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        IbashoButton(
          label: l.koenAwayOk,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Los corazones de amistad entre dos Tamas: [level] de 5 llenos.
class KoenHearts extends StatelessWidget {
  const KoenHearts({super.key, required this.level, this.size = 12});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: L.of(context)!.koenBondHearts(level),
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < koenBondSteps.length; i++)
            Padding(
              padding: EdgeInsets.only(right: size * .12),
              child: GlyphIcon(
                Glyph.heart,
                size: size,
                color: i < level ? const Color(0xFFF0628E) : Ty.inkSoft.withValues(alpha: .35),
                strokeWidth: i < level ? 2.4 : 1.6,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Una pareja de Tamas que ha subido de amistad: los dos juntos, sus
/// corazones y, al llegar a «compis», que ya tienen su baile.
class _BondUpRow extends StatelessWidget {
  const _BondUpRow({required this.up});

  final KoenBondUp up;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    Widget tama(KoenCard c, {bool flip = false}) => SizedBox(
      width: 40,
      height: 40,
      child: Transform.flip(
        flipX: flip,
        child: TamaView(
          look: c.look,
          personality: c.personality,
          name: c.name,
          voice: c.voice,
          seed: koenHash(c.tamaId),
          joy: 1,
          size: 40,
          interactive: false,
          shadow: false,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          tama(up.a),
          tama(up.b, flip: true),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.koenBondUp(up.a.name, up.b.name, l.koenBondLevel('${up.level}')), style: Ty.body),
                const SizedBox(height: 2),
                KoenHearts(level: up.level),
                if (up.level == koenBondDanceLevel) Text(l.koenBondDance, style: Ty.micro),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// El nombre de un amigo (o del amigo inventado de la prueba).
String koenFriendName(WidgetRef ref, String account) {
  if (account.startsWith('demo-')) return 'Demo ${account.substring(5)}';
  return ref.watch(cardOfProvider(account)).valueOrNull?.displayName ?? '…';
}

class _FriendUpRow extends ConsumerWidget {
  const _FriendUpRow({required this.up});

  final KoenFriendUp up;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    return Row(
      children: [
        const GlyphIcon(Glyph.friends, size: 28, color: Color(0xFFF0628E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l.koenFriendUp(koenFriendName(ref, up.friend), l.koenFriendLevel(up.level.name)),
            style: Ty.body,
          ),
        ),
        if (up.coins > 0) ...[
          const SizedBox(width: 8),
          const ArtIconView(ArtIcon.coin, size: 24),
          const SizedBox(width: 4),
          Text('+${up.coins}', style: Ty.label),
        ],
      ],
    );
  }
}

class _FoodPainter extends CustomPainter {
  _FoodPainter(this.food);

  final TamaFood food;

  @override
  void paint(Canvas canvas, Size size) => paintFood(canvas, food, size.center(Offset.zero), size.shortestSide / 2);

  @override
  bool shouldRepaint(_FoodPainter old) => old.food != food;
}

/// El botón del álbum, con cuántos recuerdos han salido.
class KoenAlbumButton extends ConsumerWidget {
  const KoenAlbumButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final count = ref.watch(koenProvider.select((k) => k.album.length));
    return IbashoButton(
      label: l.koenAlbum(count, KoenMemory.values.length),
      tone: ButtonTone.quiet,
      onPressed: onPressed,
    );
  }
}
