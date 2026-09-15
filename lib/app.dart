// Ibasho — raiz de la aplicacion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/audio_service.dart';
import 'backend/tama.dart';
import 'l10n/gen/app_localizations.dart';
import 'state/debug.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'theme/skin.dart';
import 'theme/tokens.dart';
import 'theme/type.dart';
import 'ui/canvas.dart';
import 'ui/screens/change_password_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/shell_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/tama/tama_view.dart';

/// La raiz es `WidgetsApp`, no `MaterialApp`.
///
/// Es la garantia mas fuerte de que no se cuela ni un widget de Material con
/// su aspecto por defecto: el tema de Material no llega a existir.
class IbashoApp extends ConsumerWidget {
  const IbashoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return WidgetsApp(
      title: 'Ibasho',
      color: T.cyan,
      locale: locale,
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      debugShowCheckedModeBanner: false,
      showPerformanceOverlay:
          ref.watch(debugProvider.select((d) => d.performanceOverlay)),
      pageRouteBuilder: <R>(RouteSettings settings, WidgetBuilder builder) =>
          PageRouteBuilder<R>(
        settings: settings,
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      builder: (context, navigator) {
        final accent = ref.watch(accentProvider);
        final userPrefersReduced =
            ref.watch(preferencesProvider.select((p) => p.reducedMotion));
        // La preferencia del sistema no se puede desactivar desde la app: se
        // suma a la del usuario.
        final reduced =
            userPrefersReduced || MediaQuery.of(context).disableAnimations;

        return IbashoSkin(
          accent: accent,
          reducedMotion: reduced,
          child: DefaultTextStyle(
            style: Ty.body,
            child: TamaPointerTracker(
              child: VirtualCanvas(child: navigator!),
            ),
          ),
        );
      },
      home: const AppRoot(),
    );
  }
}

/// Decide que hay en pantalla segun el estado de la sesion.
class AppRoot extends ConsumerStatefulWidget {
  const AppRoot({super.key});

  @override
  ConsumerState<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<AppRoot> {
  /// Lo que dura el splash aunque la sesion se resuelva antes. Es tiempo
  /// gastado a proposito: la campanilla de arranque tiene que sonar entera.
  static const Duration _splashHold = Duration(milliseconds: 2400);

  bool _booted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    AudioService.instance.play(Sfx.chime);
    unawaited(AudioService.instance.startMusic());
    await Future.wait<void>([
      Future<void>.delayed(_splashHold),
      ref.read(sessionProvider.notifier).restore(),
    ]);
    if (mounted) setState(() => _booted = true);
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final phase = ref.watch(sessionProvider.select((s) => s.phase));

    // Salir del entorno (cerrar sesion, sesion caducada o revocada) cierra
    // cualquier canal o dialogo abierto: si no, el login quedaria debajo de
    // la pantalla de Ajustes.
    ref.listen(sessionProvider.select((s) => s.phase), (before, after) {
      if (before == SessionPhase.active && after != SessionPhase.active) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    // El acento en uso se recuerda en local para el proximo arranque, venga
    // del perfil o del Tama.
    ref.listen(accentProvider, (before, after) {
      if (before == after || ref.read(profileProvider).profile == null) return;
      unawaited(ref.read(preferencesProvider.notifier).rememberAccent(hexFromColor(after)));
    });

    // El idioma guardado en el perfil manda sobre el local en cuanto llega.
    ref.listen(profileProvider.select((p) => p.profile?.locale), (before, after) {
      if (after == null || before == after) return;
      final preferences = ref.read(preferencesProvider);
      if (preferences.localeCode != after) {
        unawaited(ref.read(preferencesProvider.notifier).setLocale(after));
      }
    });

    final Widget screen = !_booted || phase == SessionPhase.booting
        ? const SplashScreen()
        : switch (phase) {
            SessionPhase.signedOut => const LoginScreen(),
            SessionPhase.mustChangePassword => const ChangePasswordScreen(),
            SessionPhase.active => const ShellScreen(),
            SessionPhase.booting => const SplashScreen(),
          };

    return AnimatedSwitcher(
      duration: skin.motion(const Duration(milliseconds: 420)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // El layout por defecto centra con restricciones sueltas y encogeria las
      // pantallas; aqui cada una ocupa el lienzo entero.
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(key: ValueKey<String>(screen.runtimeType.toString()), child: screen),
    );
  }
}
