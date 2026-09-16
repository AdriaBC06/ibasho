// Ibasho — cableado de dependencias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/rest_ibasho_backend.dart';
import '../storage/secure_store.dart';
import '../storage/settings_store.dart';
import '../theme/tokens.dart';
import 'accent_sync.dart';
import 'admin.dart';
import 'card.dart';
import 'friends.dart';
import 'music_library.dart';
import 'preferences.dart';
import 'presence.dart';
import 'profile.dart';
import 'session.dart';
import 'system_status.dart';
import 'tamas.dart';

/// Se sobrescriben en `main()`, cuando ya se han abierto los archivos.
final secureStoreProvider = Provider<SecureStore>(
  (_) => throw UnimplementedError('secureStoreProvider sin sobrescribir'),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError('settingsStoreProvider sin sobrescribir'),
);
final initialPreferencesProvider = Provider<Preferences>(
  (_) => throw UnimplementedError('initialPreferencesProvider sin sobrescribir'),
);

/// El unico punto del arbol que sabe que existe REST.
final backendProvider = Provider<IbashoBackend>((ref) {
  final backend = RestIbashoBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

final preferencesProvider =
    StateNotifierProvider<PreferencesController, Preferences>(
  (ref) => PreferencesController(
    ref.watch(settingsStoreProvider),
    ref.watch(initialPreferencesProvider),
  ),
);

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(
    backend: ref.watch(backendProvider),
    store: ref.watch(secureStoreProvider),
    preferences: ref.watch(preferencesProvider.notifier),
  ),
);

final clockProvider = StateNotifierProvider<Clock, DateTime>((_) => Clock());

/// De donde sale la bateria. Los tests la sustituyen: alli no hay plugins.
final batteryWatchProvider = Provider<BatteryWatch>((_) => PluginBatteryWatch());

final systemStatusProvider =
    StateNotifierProvider<SystemStatusController, SystemStatus>(
  (ref) => SystemStatusController(
    ref.watch(backendProvider),
    battery: ref.watch(batteryWatchProvider),
  ),
);

/// Vive mientras dure la sesion de un uid concreto.
final profileProvider = StateNotifierProvider<ProfileController, ProfileState>(
  (ref) {
    ref.watch(sessionProvider.select((s) => s.accountId));
    return ProfileController(
      backend: ref.watch(backendProvider),
      session: ref.watch(sessionProvider.notifier),
      defaultLocale: ref.read(preferencesProvider).localeCode,
      cardOf: (profile) => cardForProfile(ref, profile),
    );
  },
);

final adminProvider = StateNotifierProvider<AdminController, AdminState>((ref) {
  ref.watch(sessionProvider.select((s) => s.uid));
  return AdminController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// Idioma activo. Manda la preferencia local, que es la que se cambia en
/// caliente; el perfil la sincroniza cuando se guarda.
final localeProvider = Provider<Locale>(
  (ref) => Locale(ref.watch(preferencesProvider.select((p) => p.localeCode))),
);

/// Los Tamas de la cuenta en curso.
final tamasProvider = StateNotifierProvider<TamasController, TamasState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  return TamasController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    cardOf: (id, color) => cardForTama(ref, id, color),
  );
});

/// Hora con resolucion de minuto, para el humor de los Tamas. El humor se
/// calcula con esto en cada vista; no se escribe nunca.
final moodClockProvider = Provider<DateTime>((ref) {
  final minute = ref.watch(
    clockProvider.select((t) => t.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute),
  );
  return DateTime.fromMillisecondsSinceEpoch(minute * Duration.millisecondsPerMinute);
});

/// Color de acento.
///
/// Si el perfil sigue al Tama, sale del color del Tama de perfil, ajustado para
/// que se lea sobre los paneles: asi una edicion del Tama tiñe el entorno en
/// cuanto llega, sin esperar a ninguna escritura. Si no, manda el del perfil.
/// Mientras nada de eso ha llegado por red se usa el ultimo conocido en esta
/// maquina, para que el arranque no pinte cian y luego salte al color de verdad.
final accentProvider = Provider<Color>((ref) {
  final profile = ref.watch(profileProvider.select((p) => p.profile));
  if (profile != null) {
    if (profile.accentFollowsTama == true) {
      final tamaColor = ref.watch(tamasProvider.select((t) => t.profileTama?.look.color));
      if (tamaColor != null) return accentForTama(tamaColor);
    }
    return profile.accent;
  }
  final cached = ref.watch(preferencesProvider.select((p) => p.accentHex));
  return parseAccent(cached) ?? T.cyan;
});

/// `#RRGGBB` a color, o `null` si no es valido.
Color? parseAccent(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Anuncio del sistema, si lo hay. Se sigue en tiempo real.
///
/// Es opcional en el modelo de datos: cuando no existe el nodo, el panel
/// superior simplemente no ensena nada.
final announcementProvider = StreamProvider<String?>((ref) async* {
  final phase = ref.watch(sessionProvider.select((s) => s.phase));
  if (phase != SessionPhase.active) {
    yield null;
    return;
  }
  final backend = ref.watch(backendProvider);
  final session = ref.watch(sessionProvider.notifier);

  String? textOf(Object? raw) =>
      raw is Map ? raw['text'] as String? : (raw is String ? raw : null);

  try {
    yield textOf(await backend.read(
      '/system/announcement',
      idToken: await session.freshToken(),
    ));
  } catch (_) {
    yield null;
  }

  await for (final event in backend.watch(
    '/system/announcement',
    token: session.freshToken,
  )) {
    if (event.path == '/') {
      yield textOf(event.data);
    } else if (event.path == '/text') {
      yield event.data as String?;
    }
  }
});

/// Cambia el idioma en caliente y lo guarda en los dos sitios donde vive: la
/// preferencia local, que es la que manda al pintar, y el perfil, para que viaje
/// con la cuenta y no se revierta en el proximo arranque.
Future<void> changeLanguage(WidgetRef ref, String code) async {
  await ref.read(preferencesProvider.notifier).setLocale(code);
  final profile = ref.read(profileProvider).profile;
  if (profile != null && profile.locale != code) {
    await ref.read(profileProvider.notifier).save(profile.copyWith(locale: code));
  }
}

/// Musica del menu y canciones desbloqueadas de la cuenta en curso.
final musicLibraryProvider =
    StateNotifierProvider<MusicLibraryController, MusicLibraryState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  return MusicLibraryController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    preferences: ref.watch(preferencesProvider.notifier),
  );
});

/// Presencia propia. Vive mientras dure la sesion activa de una cuenta; al
/// salir se cierra su conexion y el servidor marca la desconexion.
final presenceProvider = StateNotifierProvider<PresenceController, PresenceStatus>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  final active = ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return PresenceController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    active: active,
  );
});

/// Amigos y solicitudes de la cuenta en curso.
final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return FriendsController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// Solicitudes pendientes de responder: la insignia del canal de amigos.
final pendingRequestsProvider =
    Provider<int>((ref) => ref.watch(friendsProvider.select((f) => f.incoming.length)));
