// Ibasho — deteccion de actividad, para pasar a ausente y volver.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

/// Escucha raton, toques, rueda y teclado en la raiz y avisa a la presencia.
///
/// No consume nada: los eventos siguen su camino. Avisa como mucho una vez
/// cada dos segundos, que es de sobra para "ha vuelto" y no llena de trabajo
/// cada movimiento del raton.
class ActivityWatch extends ConsumerStatefulWidget {
  const ActivityWatch({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ActivityWatch> createState() => _ActivityWatchState();
}

class _ActivityWatchState extends ConsumerState<ActivityWatch> {
  static const Duration _gap = Duration(seconds: 2);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _ping();
    return false;
  }

  void _ping() {
    final now = DateTime.now();
    if (now.difference(_last) < _gap) return;
    _last = now;
    ref.read(presenceProvider.notifier).activity();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _ping(),
        onPointerMove: (_) => _ping(),
        onPointerHover: (_) => _ping(),
        onPointerSignal: (_) => _ping(),
        child: widget.child,
      );
}
