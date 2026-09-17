// Ibasho — elegir un Tama y una cara para mandarlo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/messaging.dart';
import '../../../backend/tama.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../tama/tama_sticker.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/pressable.dart';

/// Abre la hoja de stickers. Devuelve lo elegido, o `null` si se cierra.
Future<StickerBody?> pickSticker(BuildContext context) =>
    showIbashoModal<StickerBody>(context, (_) => const _StickerSheet());

class _StickerSheet extends ConsumerStatefulWidget {
  const _StickerSheet();

  @override
  ConsumerState<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends ConsumerState<_StickerSheet> {
  int _tama = 0;
  StickerFace _face = StickerFace.happy;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;
    final tamas = ref.watch(tamasProvider).tamas;

    if (tamas.isEmpty) {
      return IbashoDialog(
        title: l.stickerOpen,
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text(l.stickerNone, style: Ty.body.copyWith(color: T.inkSoft)),
        ),
        actions: [
          IbashoButton(
            label: l.actionCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    final chosen = tamas[_tama.clamp(0, tamas.length - 1)];

    final layout = Layout.of(context);

    return IbashoDialog(
      width: tall ? 520 : 620,
      title: l.stickerOpen,
      // El dialogo no lleva desplazamiento propio: crece con lo que le metas y
      // desborda. Aqui se le pone techo y se deja rodar por dentro, para que
      // esto siga cabiendo en un movil pequeño —y para que siga cabiendo el
      // dia que haya una cara mas.
      body: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: layout.height * .62),
        child: SingleChildScrollView(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lo elegido, grande y arriba: es lo que se va a mandar, y verlo del
          // tamaño real evita mandar la cara equivocada.
          Center(
            child: TamaSticker(
              look: chosen.look,
              face: _face,
              size: tall ? 116 : 132,
              name: chosen.name,
            ),
          ),
          const SizedBox(height: 18),
          if (tamas.length > 1) ...[
            _Heading(text: l.stickerPickTama),
            const SizedBox(height: 8),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tamas.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _Choice(
                  selected: i == _tama,
                  semanticLabel: tamas[i].name,
                  onPressed: () => _choose(tama: i),
                  child: TamaSticker(
                    look: tamas[i].look,
                    face: StickerFace.happy,
                    size: 44,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _Heading(text: l.stickerPickFace),
          const SizedBox(height: 8),
          // Las ocho caras, pintadas con el Tama elegido: hay que ver lo que
          // se manda, no leer una lista de nombres. Cuatro por fila y no ocho
          // ni en el escritorio: a menos de sesenta pixeles las caras dejan de
          // distinguirse unas de otras y el selector no sirve para nada.
          _FaceGrid(
            look: chosen.look,
            selected: _face,
            columns: 4,
            onPick: (face) => _choose(face: face),
          ),
        ],
          ),
        ),
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        IbashoButton(
          label: l.stickerSend,
          glyph: Glyph.send,
          tone: ButtonTone.accent,
          cue: null,
          onPressed: () {
            AudioService.instance.play(Sfx.open);
            Navigator.of(context).pop(
              StickerBody(face: _face, name: chosen.name, look: chosen.look),
            );
          },
        ),
      ],
    );
  }

  void _choose({int? tama, StickerFace? face}) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      if (tama != null) _tama = tama;
      if (face != null) _face = face;
    });
  }
}

class _FaceGrid extends StatelessWidget {
  const _FaceGrid({
    required this.look,
    required this.selected,
    required this.columns,
    required this.onPick,
  });

  final TamaLook look;
  final StickerFace selected;
  final int columns;
  final ValueChanged<StickerFace> onPick;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    const faces = StickerFace.values;
    final rows = (faces.length / columns).ceil();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 10),
          Row(
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: 10),
                Expanded(
                  child: row * columns + col < faces.length
                      ? _Choice(
                          selected: faces[row * columns + col] == selected,
                          semanticLabel:
                              stickerFaceLabel(l, faces[row * columns + col]),
                          onPressed: () => onPick(faces[row * columns + col]),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TamaSticker(
                                look: look,
                                face: faces[row * columns + col],
                                size: 62,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                stickerFaceLabel(l, faces[row * columns + col]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Ty.caption,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Una ranura elegible: hundida cuando no lo esta, teñida cuando si.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.semanticLabel,
    required this.onPressed,
    required this.child,
  });

  final bool selected;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      cue: null,
      semanticLabel: semanticLabel,
      builder: (context, state) => FocusRing(
        visible: state.focus,
        radius: 12,
        child: GlossSurface(
          radius: 12,
          tint: selected ? skin.accent : null,
          recessed: !selected,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Ty.caption.copyWith(color: T.inkSoft),
      );
}
