// Ibasho — perfil propio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import 'session.dart';

@immutable
class ProfileState {
  const ProfileState({this.profile, this.loading = true, this.saving = false});

  final UserProfile? profile;
  final bool loading;
  final bool saving;

  ProfileState copyWith({
    UserProfile? profile,
    bool? loading,
    bool? saving,
  }) =>
      ProfileState(
        profile: profile ?? this.profile,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
      );
}

/// El perfil del usuario que ha entrado.
///
/// Se lee una vez por REST y luego se sigue en tiempo real por
/// `text/event-stream`, que es como el checkpoint quiere que se lean los datos
/// vivos desde Dart puro.
class ProfileController extends StateNotifier<ProfileState> {
  ProfileController({
    required IbashoBackend backend,
    required SessionController session,
    required String defaultLocale,
  })  : _backend = backend,
        _session = session,
        _defaultLocale = defaultLocale,
        super(const ProfileState()) {
    unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final String _defaultLocale;

  StreamSubscription<DatabaseEvent>? _watch;

  String get _path => '/users/${_session.state.accountId}/profile';

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final tokens = _session.state.tokens;
    final entry = _session.state.entry;
    if (tokens == null || entry == null) return;

    try {
      final raw = await _backend.read(_path, idToken: tokens.idToken);
      if (raw is Map) {
        state = ProfileState(profile: UserProfile.fromJson(raw), loading: false);
      } else {
        // Primera entrada: el perfil lo crea el propio usuario, porque las
        // reglas no dejan que nadie mas escriba bajo /users/$accountId.
        final seed = UserProfile(
          username: entry.username,
          displayName: entry.username,
          locale: _defaultLocale,
          timezone: localTimezoneName(),
          createdAt: DateTime.now(),
        );
        await _backend.write(_path, seed.toJson(), idToken: tokens.idToken);
        state = ProfileState(profile: seed, loading: false);
      }
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el perfil ($e)');
      state = state.copyWith(loading: false);
    }

    _watch = _backend.watch(_path, token: _session.freshToken).listen(
      _apply,
      onError: (Object e) => debugPrint('Ibasho: stream de perfil ($e)'),
    );
  }

  void _apply(DatabaseEvent event) {
    final current = state.profile;
    if (event.path == '/' ) {
      if (event.data is Map) {
        state = state.copyWith(
          profile: UserProfile.fromJson(event.data! as Map),
          loading: false,
        );
      }
      return;
    }
    if (current == null || event.data == null) return;
    final field = event.path.replaceAll('/', '');
    final value = '${event.data}';
    state = state.copyWith(
      profile: switch (field) {
        'displayName' => current.copyWith(displayName: value),
        'statusMessage' => current.copyWith(statusMessage: value),
        'birthday' => current.copyWith(birthday: value),
        'timezone' => current.copyWith(timezone: value),
        'locale' => current.copyWith(locale: value),
        'accentColor' => current.copyWith(accentColor: value),
        _ => current,
      },
    );
  }

  /// Guarda el perfil entero. Devuelve `true` si el servidor lo acepto.
  Future<bool> save(UserProfile next) async {
    final tokens = _session.state.tokens;
    if (tokens == null) return false;
    state = state.copyWith(saving: true);
    try {
      await _backend.write(_path, next.toJson(), idToken: await _session.freshToken());
      state = ProfileState(profile: next, loading: false);
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el perfil ($e)');
      state = state.copyWith(saving: false);
      return false;
    }
  }
}

/// Nombre IANA de la zona horaria del sistema.
///
/// Dart no lo expone, asi que se lee de donde lo deja el sistema; si no hay
/// suerte se cae al desplazamiento, que siempre se puede calcular.
String localTimezoneName() {
  try {
    final file = File('/etc/timezone');
    if (file.existsSync()) {
      final value = file.readAsStringSync().trim();
      if (value.isNotEmpty) return value;
    }
    final link = Link('/etc/localtime');
    if (link.existsSync()) {
      final target = link.targetSync();
      const marker = '/zoneinfo/';
      final at = target.indexOf(marker);
      if (at >= 0) return target.substring(at + marker.length);
    }
  } catch (_) {
    // Cualquier fallo cae al desplazamiento.
  }
  final offset = DateTime.now().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final hours = offset.inHours.abs().toString().padLeft(2, '0');
  final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$minutes';
}
