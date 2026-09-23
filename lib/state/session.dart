// Ibasho — ciclo de vida de la sesion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../storage/secure_store.dart';
import 'preferences.dart';

enum SessionPhase {
  /// Todavia se esta comprobando si hay una sesion guardada.
  booting,

  /// No hay nadie dentro.
  signedOut,

  /// Credenciales validas, pero la contrasena es la de un solo uso.
  mustChangePassword,

  /// Dentro del entorno.
  active,
}

/// Motivo por el que se volvio al login. La interfaz lo traduce.
enum SignOutReason { none, expired, revoked, notAllowed }

@immutable
class SessionState {
  const SessionState({
    required this.phase,
    this.tokens,
    this.entry,
    this.isAdmin = false,
    this.reason = SignOutReason.none,
  });

  const SessionState.booting() : this(phase: SessionPhase.booting);

  final SessionPhase phase;
  final AuthTokens? tokens;
  final AllowlistEntry? entry;
  final bool isAdmin;
  final SignOutReason reason;

  /// Uid de la identidad con la que se ha entrado.
  String get uid => tokens?.uid ?? '';

  /// Cuenta estable de la persona. Es la raiz de todos sus datos.
  String get accountId => entry?.accountId ?? '';

  String get username => entry?.username ?? '';
}

const String _tokensKey = 'ibasho.session.tokens';

/// Mantiene la sesion viva: la restaura al arrancar, la renueva un minuto
/// antes de que caduque y la tira en cuanto el servidor la revoca.
class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required IbashoBackend backend,
    required SecureStore store,
    required PreferencesController preferences,
  })  : _backend = backend,
        _store = store,
        _preferences = preferences,
        super(const SessionState.booting());

  final IbashoBackend _backend;
  final SecureStore _store;
  final PreferencesController _preferences;

  Timer? _renewal;
  Completer<void>? _renewing;

  @override
  void dispose() {
    _renewal?.cancel();
    super.dispose();
  }

  // --- Arranque ----------------------------------------------------------

  Future<void> restore() async {
    final raw = await _store.read(_tokensKey);
    if (raw == null) {
      state = const SessionState(phase: SessionPhase.signedOut);
      return;
    }
    try {
      var tokens = AuthTokens.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
      if (DateTime.now().isAfter(tokens.renewAt)) {
        tokens = await _backend.refresh(tokens.refreshToken);
      }
      await _enter(tokens);
    } on IbashoException catch (e) {
      debugPrint('Ibasho: la sesion guardada no sirve (${e.failure.name})');
      await _forget(
        e.failure == IbashoFailure.network
            ? SignOutReason.none
            : SignOutReason.expired,
      );
    }
  }

  // --- Entrada y salida --------------------------------------------------

  /// Inicia sesion. Lanza `IbashoException` para que la pantalla de login
  /// decida que mensaje ensena.
  Future<void> signIn({required String username, required String password}) async {
    final name = username.trim().toLowerCase();
    final known = _preferences.state.credentialGenerations[name] ?? 1;
    final result = await _backend.signIn(
      username: name,
      password: password,
      knownGeneration: known,
    );
    await _preferences.rememberCredential(name, result.generation);
    await _enter(result.tokens);
  }

  /// Aplica la contrasena definitiva y entra en el entorno.
  Future<void> completePasswordChange(String newPassword) async {
    final tokens = state.tokens;
    if (tokens == null) throw const IbashoException(IbashoFailure.tokenExpired);
    final renewed =
        await _backend.changePassword(session: tokens, newPassword: newPassword);
    await _backend.write(
      '/allowlist/${renewed.uid}/mustChangePassword',
      false,
      idToken: renewed.idToken,
    );
    await _enter(renewed);
  }

  /// Cambio de contrasena voluntario, desde Ajustes.
  ///
  /// Pide la contrasena actual y la comprueba iniciando sesion con ella antes
  /// de tocar nada: un token abierto no basta para cambiar la llave.
  Future<void> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final entry = state.entry;
    if (entry == null) throw const IbashoException(IbashoFailure.tokenExpired);
    final check = await _backend.signIn(
      username: entry.username,
      password: currentPassword,
      knownGeneration: entry.generation,
    );
    if (check.tokens.uid != state.uid) {
      throw const IbashoException(IbashoFailure.invalidCredentials);
    }
    final renewed = await _backend.changePassword(
      session: check.tokens,
      newPassword: newPassword,
    );
    state = SessionState(
      phase: state.phase,
      tokens: renewed,
      entry: entry,
      isAdmin: state.isAdmin,
    );
    await _persist(renewed);
    _scheduleRenewal(renewed);
  }

  /// Sale de la sesion. La presencia no se toca aqui: al cambiar de cuenta se
  /// cierra la conexion de presencia y el servidor marca la desconexion por
  /// su cuenta (o no, si se estaba invisible).
  Future<void> signOut({SignOutReason reason = SignOutReason.none}) => _forget(reason);

  // --- Tokens ------------------------------------------------------------

  /// Token de identidad valido ahora mismo, renovandolo si hace falta.
  ///
  /// Es lo que consumen las suscripciones en tiempo real cada vez que se
  /// reconectan.
  Future<String> freshToken() async {
    final tokens = state.tokens;
    if (tokens == null) throw const IbashoException(IbashoFailure.tokenExpired);
    if (DateTime.now().isBefore(tokens.renewAt)) return tokens.idToken;
    await _renew();
    final renewed = state.tokens;
    if (renewed == null) throw const IbashoException(IbashoFailure.tokenExpired);
    return renewed.idToken;
  }

  /// La app vuelve tras un rato en segundo plano (quiza horas).
  ///
  /// Los temporizadores no corren con el proceso dormido, asi que la
  /// renovacion programada puede no haber llegado: si el token ya esta cerca
  /// de caducar se renueva ahora, antes de que nada lo use, y se vuelve a
  /// programar la siguiente.
  Future<void> resume() async {
    final tokens = state.tokens;
    if (tokens == null) return;
    if (DateTime.now().isBefore(tokens.renewAt)) {
      _scheduleRenewal(tokens);
      return;
    }
    try {
      await _renew();
    } catch (e) {
      debugPrint('Ibasho: renovacion al volver fallida ($e)');
    }
  }

  Future<void> _renew() async {
    if (_renewing != null) return _renewing!.future;
    final gate = _renewing = Completer<void>();
    try {
      final tokens = state.tokens;
      if (tokens == null) throw const IbashoException(IbashoFailure.tokenExpired);
      final renewed = await _backend.refresh(tokens.refreshToken);
      state = SessionState(
        phase: state.phase,
        tokens: renewed,
        entry: state.entry,
        isAdmin: state.isAdmin,
      );
      await _persist(renewed);
      _scheduleRenewal(renewed);
      gate.complete();
    } on IbashoException catch (e) {
      gate.completeError(e);
      if (e.failure == IbashoFailure.network) {
        // Sin red no se tira la sesion: se reintenta pronto.
        _renewal?.cancel();
        _renewal = Timer(const Duration(seconds: 20), () => unawaited(_renew()));
      } else {
        await _forget(SignOutReason.revoked);
      }
    } finally {
      _renewing = null;
    }
  }

  void _scheduleRenewal(AuthTokens tokens) {
    _renewal?.cancel();
    final wait = tokens.renewAt.difference(DateTime.now());
    _renewal = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(_renew().catchError((_) {})),
    );
  }

  // --- Interno -----------------------------------------------------------

  /// Comprueba la pertenencia a la allowlist y coloca la sesion en su sitio.
  ///
  /// Las reglas de la base no dejan leer nada a quien no esta en la allowlist,
  /// asi que una cuenta creada por fuera de la app falla justo aqui.
  Future<void> _enter(AuthTokens tokens) async {
    late final AllowlistEntry entry;
    try {
      final raw = await _backend.read('/allowlist/${tokens.uid}', idToken: tokens.idToken);
      if (raw is! Map) {
        await _forget(SignOutReason.notAllowed);
        throw const IbashoException(IbashoFailure.notAllowed);
      }
      entry = AllowlistEntry.fromJson(tokens.uid, raw);
    } on IbashoException catch (e) {
      if (e.failure == IbashoFailure.permissionDenied) {
        await _forget(SignOutReason.notAllowed);
        throw const IbashoException(IbashoFailure.notAllowed);
      }
      rethrow;
    }

    // Una identidad retirada es una credencial que ya se regenero: para quien
    // la usa, simplemente esa contrasena ha dejado de valer.
    if (entry.retired) {
      await _forget(SignOutReason.none);
      throw const IbashoException(IbashoFailure.invalidCredentials);
    }

    if (entry.disabled) {
      await _forget(SignOutReason.notAllowed);
      throw const IbashoException(IbashoFailure.accountDisabled);
    }

    var isAdmin = false;
    try {
      isAdmin = await _backend.read('/admins/${tokens.uid}', idToken: tokens.idToken) == true;
    } catch (_) {
      // No poder leerlo significa no serlo.
    }

    await _persist(tokens);
    _scheduleRenewal(tokens);

    // A partir de aqui todos los nodos de la cuenta comparten una sola
    // conexion en tiempo real; hay que decirle al backend cual es la cuenta
    // antes de que ningun controlador se ponga a mirar.
    _backend.setOwnAccount(entry.accountId);

    if (entry.mustChangePassword) {
      state = SessionState(
        phase: SessionPhase.mustChangePassword,
        tokens: tokens,
        entry: entry,
        isAdmin: isAdmin,
      );
      return;
    }

    state = SessionState(
      phase: SessionPhase.active,
      tokens: tokens,
      entry: entry,
      isAdmin: isAdmin,
    );
  }

  Future<void> _persist(AuthTokens tokens) =>
      _store.write(_tokensKey, jsonEncode(tokens.toJson()));

  Future<void> _forget(SignOutReason reason) async {
    _renewal?.cancel();
    _renewal = null;
    await _store.delete(_tokensKey);
    _backend.setOwnAccount(null);
    state = SessionState(phase: SessionPhase.signedOut, reason: reason);
  }
}
