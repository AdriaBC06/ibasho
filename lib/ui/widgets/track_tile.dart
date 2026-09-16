// Ibasho — fila de una pista de musica.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../layout.dart';
import 'glyphs.dart';
import 'gloss.dart';
import 'pressable.dart';

/// Una pista en una lista: elegida (plastico tenido) o disponible (hueco).
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onPressed,
    this.trailing,
    this.dimmed = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onPressed;

  /// Lo que va a la derecha: una etiqueta de estado o un boton.
  final Widget? trailing;

  /// Pista bloqueada: se ensena, pero apagada.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final onTint = selected ? T.onAccent : null;
    final tall = Layout.of(context).tall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Pressable(
        onPressed: selected ? null : onPressed,
        builder: (context, state) => Opacity(
          opacity: dimmed ? .55 : 1,
          child: GlossSurface(
            radius: 16,
            tint: selected ? skin.accent : null,
            recessed: !selected,
            elevation: selected ? 1 : 0,
            borderColor: selected
                ? skin.accentDeep
                : Color.lerp(T.hairline, skin.accentDeep,
                    onPressed == null ? 0 : state.hover)!,
            padding: EdgeInsets.symmetric(horizontal: tall ? 14 : 18, vertical: 11),
            child: tall
                // En vertical: el nombre con su icono arriba, lo demas debajo.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          GlyphIcon(
                            selected ? Glyph.speaker : (dimmed ? Glyph.lock : Glyph.play),
                            size: 22,
                            color: onTint ?? skin.accentDeep,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.lead.copyWith(color: onTint ?? T.ink),
                            ),
                          ),
                          if (trailing != null)
                            Flexible(
                              child: DefaultTextStyle.merge(
                                style: TextStyle(color: onTint),
                                child: trailing!,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.caption.copyWith(color: onTint ?? T.inkSoft, height: 1.3),
                      ),
                    ],
                  )
                : Row(
              children: [
                GlyphIcon(
                  selected ? Glyph.speaker : (dimmed ? Glyph.lock : Glyph.play),
                  size: 22,
                  color: onTint ?? skin.accentDeep,
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 100,
                  child: Text(
                    title,
                    style: Ty.lead.copyWith(color: onTint ?? T.ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.caption.copyWith(
                      color: onTint ?? T.inkSoft,
                      height: 1.3,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  DefaultTextStyle.merge(
                    style: TextStyle(color: onTint),
                    child: trailing!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

