// Ibasho — piezas de Tamakoro: el lienzo, los asientos del coro y el selector.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../../ui/layout.dart';
import '../../ui/tama/tama_view.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/gloss.dart';
import '../../ui/widgets/glyphs.dart';
import '../../ui/widgets/overlays.dart';
import '../../ui/widgets/pressable.dart';
import 'koro_song.dart';

/// El titulo de una cancion. No se edita: sale del numero y de quien la hizo.
String koroTitle(L l, KoroSong song, String owner) => l.koroSongTitle(song.number, owner);

/// El color de tinta de cada asiento: el del cuerpo de su Tama. Si se parece
/// mucho al de un asiento anterior, se oscurece para que se distingan en el
/// lienzo. Un asiento vacio pinta en gris.
List<Color> koroInks(KoroSong song, List<Tama> tamas) {
  final inks = <Color>[];
  for (final id in song.seats) {
    final tama = tamas.where((t) => t.id == id).firstOrNull;
    var color = tama?.look.bodyColor ?? Ty.inkSoft;
    for (var tries = 0; tries < 3 && inks.any((c) => _close(c, color)); tries++) {
      color = Color.lerp(color, Ty.ink, .38)!;
    }
    inks.add(color);
  }
  return inks;
}

bool _close(Color a, Color b) {
  final dr = (a.r - b.r) * 255, dg = (a.g - b.g) * 255, db = (a.b - b.b) * 255;
  return math.sqrt(dr * dr + dg * dg + db * db) < 60;
}

/// Pinta la partitura: rejilla, tinta y, si [playhead] no es `null`, el
/// cabezal (en pasos, con decimales).
class KoroCanvasPainter extends CustomPainter {
  KoroCanvasPainter({
    required this.song,
    required this.inks,
    this.playhead,
    this.grid = true,
    this.accent = T.cyan,
    super.repaint,
  });

  final KoroSong song;
  final List<Color> inks;
  final ValueListenable<double?>? playhead;
  final bool grid;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / koroSteps;
    final ch = size.height / koroRows;
    if (grid) {
      final thin = Paint()
        ..color = T.hairline.withValues(alpha: .45)
        ..strokeWidth = 1;
      final beat = Paint()
        ..color = T.hairline
        ..strokeWidth = 1.2;
      for (var s = 1; s < koroSteps; s++) {
        final x = s * cw;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), s % 4 == 0 ? beat : thin);
      }
      // Las filas de la tonica, un poco mas marcadas: ayudan a orientarse.
      for (var r = 1; r < koroRows; r++) {
        final y = size.height - r * ch;
        canvas.drawLine(Offset(0, y), Offset(size.width, y),
            r % song.scale.steps.length == 0 ? beat : thin);
      }
    }
    final pad = math.min(cw, ch) * (grid ? .12 : 0);
    for (final note in song.notes) {
      final rect = Rect.fromLTWH(
        note.start * cw + pad,
        size.height - (note.row + 1) * ch + pad,
        note.length * cw - pad * 2,
        ch - pad * 2,
      );
      final color = inks.elementAtOrNull(note.seat) ?? Ty.inkSoft;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(math.min(rect.height, rect.width) / 2)),
        Paint()..color = color,
      );
    }
    final head = playhead?.value;
    if (head != null) {
      final x = head * cw;
      canvas.drawRect(
        Rect.fromLTWH(x - cw * .5, 0, cw, size.height),
        Paint()..color = accent.withValues(alpha: .14),
      );
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = accent
          ..strokeWidth = 2.4,
      );
    }
  }

  @override
  bool shouldRepaint(KoroCanvasPainter old) =>
      old.song != song || old.inks != inks || old.grid != grid || old.accent != accent;
}

/// Un Tama pequeño, quieto, para asientos y listas.
class KoroTamaFace extends StatelessWidget {
  const KoroTamaFace({super.key, required this.tama, required this.size});

  final Tama tama;
  final double size;

  @override
  Widget build(BuildContext context) => TamaView(
        look: tama.look,
        personality: tama.personality,
        name: tama.name,
        voice: tama.voice,
        size: size,
        interactive: false,
        shadow: false,
      );
}

/// Un asiento del coro: el Tama sobre una ficha de su color. Elegido, es el
/// pincel con el que se pinta.
class KoroSeat extends StatelessWidget {
  const KoroSeat({
    super.key,
    required this.tama,
    required this.ink,
    required this.selected,
    required this.onPressed,
    this.onLongPress,
    this.size = 58,
  });

  final Tama? tama;
  final Color ink;
  final bool selected;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final tama = this.tama;
    return GestureDetector(
      onLongPress: onLongPress,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: tama?.name,
        builder: (context, press) => AnimatedContainer(
          duration: skin.motion(T.hover),
          width: size,
          height: size,
          transform: Matrix4.translationValues(0, -3 * press.hover, 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? skin.accentDeep : skin.hairline, width: selected ? 3 : 1.4),
          ),
          padding: const EdgeInsets.all(3),
          child: tama == null
              ? GlossSurface(
                  radius: size,
                  recessed: true,
                  child: Center(child: GlyphIcon(Glyph.plus, size: size * .34, color: Ty.inkSoft)),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    GlossSurface(radius: size, tint: ink.withValues(alpha: .55)),
                    KoroTamaFace(tama: tama, size: size * .78),
                  ],
                ),
        ),
      ),
    );
  }
}

/// El selector de Tamas: una rejilla con los de la cuenta. Devuelve el
/// elegido, `''` para dejar el asiento libre o `null` si se cierra sin mas.
Future<String?> pickKoroTama(
  BuildContext context, {
  required List<Tama> tamas,
  required String title,
  bool allowClear = false,
}) {
  final l = L.of(context)!;
  return showIbashoModal<String>(
    context,
    (context) {
      final layout = Layout.of(context);
      final cell = layout.tall ? 76.0 : 88.0;
      return IbashoDialog(
        title: title,
        body: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: layout.tall ? 320 : 360),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tama in tamas)
                  Pressable(
                    onPressed: () => Navigator.of(context).pop(tama.id),
                    semanticLabel: tama.name,
                    builder: (context, press) => SizedBox(
                      width: cell,
                      child: Column(
                        children: [
                          AnimatedSlide(
                            duration: IbashoSkin.of(context).motion(T.hover),
                            offset: Offset(0, -.04 * press.hover),
                            child: KoroTamaFace(tama: tama, size: cell * .8),
                          ),
                          Text(tama.name, style: Ty.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (allowClear)
            IbashoButton(
              label: l.koroSeatClear,
              onPressed: () => Navigator.of(context).pop(''),
            ),
          IbashoButton(
            label: l.actionCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}

/// Flechas y puntos de pagina, como en el mostrador del Yatai.
class KoroPager extends StatelessWidget {
  const KoroPager({super.key, required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconPill(
          glyph: Glyph.arrowLeft,
          diameter: layout.pill,
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
          glyph: Glyph.arrowRight,
          diameter: layout.pill,
          onPressed: page < pages - 1 ? () => onPage(page + 1) : null,
        ),
      ],
    );
  }
}
