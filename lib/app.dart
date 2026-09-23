// Ibasho — raiz de la aplicacion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio/audio_service.dart';
import 'backend/tama.dart';
import 'core/device.dart';
import 'l10n/gen/app_localizations.dart';
import 'state/debug.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'state/update_gate.dart';
import 'theme/accent.dart';
import 'theme/menu_theme.dart';
import 'theme/skin.dart';
import 'theme/tokens.dart';
import 'theme/type.dart';
import 'ui/canvas.dart';
import 'ui/mobile.dart';
import 'ui/screens/change_password_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/shell_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/screens/update_required_screen.dart';
import 'ui/tama/tama_view.dart';
import 'ui/touch.dart';

/// La raiz es `WidgetsApp`, no `MaterialApp`.
///
/// Es la garantia mas fuerte de que no se cuela ni un widget de Material con
/// su aspecto por defecto: el tema de Material no llega a existir.
class IbashoApp extends ConsumerStatefulWidget {
  const IbashoApp({super.key});

  @override
  ConsumerState<IbashoApp> createState() => _IbashoAppState();
}

class _IbashoAppState extends ConsumerState<IbashoApp> {
  final BackGate _back = BackGate();

  @override
  void initState() {
    super.initState();
    // Antes que WidgetsApp: el boton de atras del sistema pasa primero por
    // aqui.
    WidgetsBinding.instance.addObserver(_back);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_back);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    // La cancion de Tamakoro del menu se mantiene al dia en cualquier pantalla.
    ref.watch(koroMenuMusicProvider);

    return WidgetsApp(
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [topRouteTracker],
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
        // El tema del fondo puesto tine los materiales y, si se quiere,
        // da el acento.
        final theme = menuThemeFor(ref.watch(backdropIdProvider));
        final followsTheme =
            ref.watch(preferencesProvider.select((p) => p.accentFollowsTheme));
        final glassLevel =
            ref.watch(preferencesProvider.select((p) => p.glassLevel));
        final surfaces =
            (theme?.surfaces ?? Surfaces.house).withGlassLevel(glassLevel);
        _applyInk(surfaces);
        final chosen = followsTheme && theme != null
            ? theme.accent
            : ref.watch(accentProvider);
        // Sobre plastico negro un acento oscuro no se ve: se aclara.
        final accent = surfaces.dark ? brightAccent(chosen) : chosen;
        final userPrefersReduced =
            ref.watch(preferencesProvider.select((p) => p.reducedMotion));
        // La preferencia del sistema no se puede desactivar desde la app: se
        // suma a la del usuario.
        final reduced =
            userPrefersReduced || MediaQuery.of(context).disableAnimations;

        return IbashoSkin(
          accent: accent,
          reducedMotion: reduced,
          surfaces: surfaces,
          child: DefaultTextStyle(
            style: Ty.body,
            child: MobileLifecycle(
              child: TamaPointerTracker(
                child: TouchAssist(
                  child: VirtualCanvas(child: navigator!),
                ),
              ),
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
    final locked = ref.watch(updateLockedProvider);

    // Si llega una version minima mayor con la app abierta, se cierra todo lo
    // que haya encima y se ensena el aviso.
    ref.listen(updateLockedProvider, (before, after) {
      if (after && before != true) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

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
        : locked
        ? const UpdateRequiredScreen()
        : switch (phase) {
            SessionPhase.signedOut => const LoginScreen(),
            SessionPhase.mustChangePassword => const ChangePasswordScreen(),
            SessionPhase.active => const ShellScreen(),
            SessionPhase.booting => const SplashScreen(),
          };

    final switcher = AnimatedSwitcher(
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

    // En Android la raiz nunca se cierra sola: asi el sistema entrega siempre
    // el gesto de atras a la app, y BackGate pregunta antes de salir.
    return PopScope(canPop: !Device.isAndroid, child: switcher);
  }
}

/// Pone la tinta del tema en los estilos de texto ([Ty.ink], [Ty.inkSoft]).
///
/// Los estilos se leen al construir y los pintores al pintar, y muchos no
/// dependen de la piel (son `const` o no la miran), asi que al pasar de un
/// tema claro a uno oscuro se redibuja la app entera una vez, como tras una
/// recarga en caliente: conserva el estado y no toca la cache de imagenes.
void _applyInk(Surfaces surfaces) {
  if (Ty.ink == surfaces.ink && Ty.inkSoft == surfaces.inkSoft) return;
  Ty.ink = surfaces.ink;
  Ty.inkSoft = surfaces.inkSoft;
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => unawaited(WidgetsBinding.instance.reassembleApplication()),
  );
}
