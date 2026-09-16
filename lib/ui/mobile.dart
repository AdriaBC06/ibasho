// Ibasho — lo que solo existe en el movil: ciclo de vida, atras e inmersivo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../core/device.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/providers.dart';
import 'widgets/controls.dart';
import 'widgets/overlays.dart';

/// Navegador de toda la app. Lo necesita el boton de atras del sistema, que
/// llega de fuera del arbol.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Sigue cual es la ruta de arriba del navegador.
class TopRouteTracker extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  Route<dynamic>? get top => _stack.isEmpty ? null : _stack.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _stack.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (index >= 0 && newRoute != null) {
      _stack[index] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
  }
}

final TopRouteTracker topRouteTracker = TopRouteTracker();

/// El boton y el gesto de atras de Android.
///
/// Hacen exactamente lo que ya hace la vuelta atras de la interfaz: cierran el
/// dialogo o la pagina de arriba con su sonido de retroceso. Una pagina que
/// no se deja cerrar sin preguntar (el creador con cambios) lo decide ella con
/// su `PopScope`. En la raiz no se cierra la app a la primera: se pregunta.
///
/// Se registra antes que `WidgetsApp`, asi que es el primero en enterarse.
class BackGate with WidgetsBindingObserver {
  bool _asking = false;

  @override
  Future<bool> didPopRoute() async {
    if (!Device.isAndroid) return false;
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return false;

    if (navigator.canPop()) {
      final top = topRouteTracker.top;
      final guarded = top is ModalRoute && top.popDisposition == RoutePopDisposition.doNotPop;
      if (!guarded) AudioService.instance.play(Sfx.back);
      await navigator.maybePop();
      return true;
    }

    if (_asking) return true;
    _asking = true;
    try {
      final context = navigator.context;
      final l = L.of(context)!;
      final leave = await askConfirmation(
        context,
        title: l.exitConfirmTitle,
        body: l.exitConfirmBody,
        confirmLabel: l.exitConfirm,
        cancelLabel: l.exitStay,
        tone: ButtonTone.warn,
      );
      if (leave) await SystemNavigator.pop();
    } finally {
      _asking = false;
    }
    return true;
  }
}

/// Oculta las barras del sistema: el entorno ocupa la pantalla entera, como
/// una consola. Deslizar desde el borde las devuelve un momento.
///
/// Android las vuelve a ensenar por su cuenta en cuanto pasa algo (se abre el
/// teclado, se gira el movil), asi que ademas se queda escuchando y las
/// esconde otra vez unos segundos despues.
Future<void> applyImmersiveMode() async {
  if (!Device.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIChangeCallback((visible) async {
    if (!visible) return;
    await Future<void>.delayed(const Duration(seconds: 3));
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });
}

/// Primer plano y segundo plano en el movil.
///
/// Al irse: la musica y los efectos callan y sueltan el foco, la presencia
/// pasa a ausente y cierra su websocket, las suscripciones en tiempo real se
/// cierran y ningun reloj ni sondeo sigue latiendo. Al volver: la sesion se
/// renueva si ha caducado mientras dormia, y todo lo demas se reabre.
///
/// En escritorio no hace nada: minimizar una ventana no es irse.
class MobileLifecycle extends ConsumerStatefulWidget {
  const MobileLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MobileLifecycle> createState() => _MobileLifecycleState();
}

class _MobileLifecycleState extends ConsumerState<MobileLifecycle> {
  AppLifecycleListener? _listener;
  bool _away = false;
  Future<void> _transition = Future<void>.value();

  @override
  void initState() {
    super.initState();
    if (Device.isAndroid) {
      _listener = AppLifecycleListener(onStateChange: _onState);
    }
  }

  @override
  void dispose() {
    _listener?.dispose();
    super.dispose();
  }

  void _onState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_away) return;
        _away = true;
        _serial(_goAway);
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        _serial(_comeBack);
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Irse y volver muy rapido no se pisa: cada paso espera al anterior.
  void _serial(Future<void> Function() step) {
    _transition = _transition.then((_) => step()).catchError((Object e) {
      debugPrint('Ibasho: cambio de ciclo de vida fallido ($e)');
    });
  }

  Future<void> _goAway() async {
    ref.read(clockProvider.notifier).pause();
    ref.read(systemStatusProvider.notifier).pause();
    ref.read(backendProvider).setBackground(true);
    await Future.wait<void>([
      AudioService.instance.suspend(),
      ref.read(presenceProvider.notifier).suspend(),
    ]);
  }

  Future<void> _comeBack() async {
    ref.read(clockProvider.notifier).resume();
    unawaited(applyImmersiveMode());
    unawaited(AudioService.instance.resume());
    await ref.read(sessionProvider.notifier).resume();
    ref.read(backendProvider).setBackground(false);
    ref.read(systemStatusProvider.notifier).resume();
    await ref.read(presenceProvider.notifier).resume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
