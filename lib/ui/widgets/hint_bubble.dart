// Ibasho — globo de ayuda: explica una píldora al pasar el ratón o al tocarla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/type.dart';
import 'gloss.dart';

/// Envuelve [child] para que, al pasar el ratón por encima o al tocarlo,
/// salga encima un globo con [message]. Tocado, se cierra solo a los pocos
/// segundos o al tocar otra vez. Si hay [onPressed], tocar hace eso en vez de
/// abrir el globo (el globo sigue saliendo con el ratón).
class HintBubble extends StatefulWidget {
  const HintBubble({super.key, required this.message, required this.child, this.onPressed});

  final String message;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<HintBubble> createState() => _HintBubbleState();
}

class _HintBubbleState extends State<HintBubble> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _hide;

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show({Duration? for_}) {
    _hide?.cancel();
    if (!_portal.isShowing) setState(_portal.show);
    if (for_ != null) _hide = Timer(for_, _close);
  }

  void _close() {
    _hide?.cancel();
    if (mounted && _portal.isShowing) setState(_portal.hide);
  }

  void _tap() {
    if (widget.onPressed != null) {
      _close();
      widget.onPressed!();
      return;
    }
    if (_portal.isShowing) {
      _close();
    } else {
      AudioService.instance.play(Sfx.tick);
      _show(for_: const Duration(seconds: 4));
    }
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.topCenter,
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -6),
          child: IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: GlossSurface(
                radius: 12,
                elevation: 1.4,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(widget.message, textAlign: TextAlign.center, style: Ty.caption.copyWith(color: Ty.ink)),
              ),
            ),
          ),
        ),
      ),
      child: Semantics(
        hint: widget.message,
        button: widget.onPressed != null,
        child: MouseRegion(
          cursor: widget.onPressed != null ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _show(),
          onExit: (_) => _close(),
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: widget.child),
        ),
      ),
    ),
  );
}
