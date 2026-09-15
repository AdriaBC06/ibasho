// Ibasho — alta y gestion de cuentas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/errors.dart';
import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../core/friend_code.dart';
import 'session.dart';

/// Alfabeto de las contrasenas generadas.
///
/// Sin caracteres ambiguos: fuera la ele minuscula, el uno, la i mayuscula, la
/// o mayuscula y el cero. Una credencial se dicta en voz alta mas veces de las
/// que uno cree.
const String _alphabet =
    'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int _passwordLength = 16;

final RegExp usernamePattern = RegExp(r'^[a-z0-9_]{3,16}$');

/// Genera una contrasena con `Random.secure()`.
String generatePassword([Random? source]) {
  final random = source ?? Random.secure();
  return String.fromCharCodes(
    List<int>.generate(
      _passwordLength,
      (_) => _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
    ),
  );
}

@immutable
class AdminState {
  const AdminState({
    this.accounts = const <AllowlistEntry>[],
    this.loading = true,
    this.busy = false,
  });

  final List<AllowlistEntry> accounts;
  final bool loading;
  final bool busy;

  AdminState copyWith({
    List<AllowlistEntry>? accounts,
    bool? loading,
    bool? busy,
  }) =>
      AdminState(
        accounts: accounts ?? this.accounts,
        loading: loading ?? this.loading,
        busy: busy ?? this.busy,
      );
}

/// El panel de administracion.
///
/// Solo existe para un uid que este en `/admins`; las reglas de la base lo
/// vuelven a comprobar en cada escritura, asi que esconder el canal es
/// comodidad, no seguridad.
class AdminController extends StateNotifier<AdminState> {
  AdminController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(const AdminState()) {
    unawaited(_start());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  StreamSubscription<DatabaseEvent>? _watch;

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final raw = await _backend.read('/allowlist', idToken: await _session.freshToken());
      state = state.copyWith(accounts: _parse(raw), loading: false);
      unawaited(assignMissingFriendCodes());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido listar la allowlist ($e)');
      state = state.copyWith(loading: false);
    }
    _watch = _backend.watch('/allowlist', token: _session.freshToken).listen(
      (event) {
        // Cualquier cambio en el arbol se resuelve releyendo el nodo: la lista
        // es corta y asi no hay que aplicar parches a mano.
        if (event.path == '/' && event.data is Map?) {
          state = state.copyWith(accounts: _parse(event.data), loading: false);
        } else {
          unawaited(refresh());
        }
      },
      onError: (Object e) => debugPrint('Ibasho: stream de allowlist ($e)'),
    );
  }

  /// Una fila por persona: las identidades retiradas por una regeneracion no
  /// se ensenan, solo la vigente de cada cuenta.
  static List<AllowlistEntry> _parse(Object? raw) {
    if (raw is! Map) return const <AllowlistEntry>[];
    final entries = <AllowlistEntry>[];
    raw.forEach((uid, value) {
      if (value is! Map) return;
      final entry = AllowlistEntry.fromJson('$uid', value);
      if (!entry.retired) entries.add(entry);
    });
    entries.sort((a, b) => a.username.compareTo(b.username));
    return entries;
  }

  Future<void> refresh() async {
    try {
      final raw = await _backend.read('/allowlist', idToken: await _session.freshToken());
      state = state.copyWith(accounts: _parse(raw), loading: false);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido refrescar la allowlist ($e)');
    }
  }

  /// Da de alta una cuenta y devuelve su credencial de un solo uso.
  Future<ProvisionedAccount> createAccount(
    String rawUsername, {
    String? password,
  }) async {
    final username = rawUsername.trim().toLowerCase();
    if (!usernamePattern.hasMatch(username)) {
      throw const IbashoException(IbashoFailure.unknown, 'username');
    }
    state = state.copyWith(busy: true);
    try {
      final token = await _session.freshToken();
      final taken = await _backend.read('/usernames/$username', idToken: token);
      if (taken != null) {
        throw const IbashoException(IbashoFailure.usernameTaken);
      }

      // Aislada: los tokens que devuelve `accounts:signUp` se descartan dentro
      // del backend y la sesion del administrador no se entera.
      final account = await _backend.provisionAccount(
        username: username,
        password: password ?? generatePassword(),
      );

      // La primera identidad de una cuenta presta su uid como identificador
      // estable. A partir de aqui ese valor ya no cambia nunca. Entrada,
      // nombre y codigo de amigo van en una sola operacion, con el contador.
      await _withNextCode(token, (counter, code) => {
            'allowlist/${account.uid}': _entryJson(
              uid: account.uid,
              accountId: account.uid,
              username: username,
              generation: 1,
            ),
            'usernames/$username': account.uid,
            ..._codeWrites(account.uid, counter, code),
          });
      await refresh();
      return account;
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Emite una credencial nueva para alguien que ha perdido la suya, sin
  /// perder ni un dato.
  ///
  /// Identity Toolkit no deja cambiar la contrasena de otra persona sin
  /// credenciales de servicio, asi que se emite una identidad de inicio de
  /// sesion nueva (la generacion siguiente del email interno) que apunta al
  /// **mismo** `accountId`. Los datos cuelgan de ese identificador, no del uid,
  /// asi que siguen exactamente donde estaban. La identidad anterior queda
  /// retirada: deshabilitada para siempre y fuera de la lista.
  Future<ProvisionedAccount> regenerateCredential(AllowlistEntry entry) async {
    state = state.copyWith(busy: true);
    try {
      final token = await _session.freshToken();
      final password = generatePassword();
      final generation = entry.generation + 1;
      final account = await _backend.provisionAccount(
        username: entry.username,
        password: password,
        generation: generation,
      );

      // 1. La identidad nueva, colgando de la misma cuenta.
      await _writeEntry(
        uid: account.uid,
        accountId: entry.accountId,
        username: entry.username,
        generation: generation,
        token: token,
      );

      // 2. Si era administracion, la identidad nueva hereda el permiso antes
      //    de que la vieja lo pierda, para no dejar nunca la cuenta sin el.
      final wasAdmin =
          await _backend.read('/admins/${entry.uid}', idToken: token) == true;
      if (wasAdmin) {
        await _backend.write('/admins/${account.uid}', true, idToken: token);
      }

      // 3. Se retira la vieja.
      await _backend.merge(
        '/allowlist/${entry.uid}',
        {'disabled': true, 'retired': true},
        idToken: token,
      );
      if (wasAdmin) {
        await _backend.remove('/admins/${entry.uid}', idToken: token);
      }

      await refresh();
      return ProvisionedAccount(
        uid: account.uid,
        username: entry.username,
        password: account.password,
      );
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  Future<void> setDisabled(AllowlistEntry entry, bool disabled) async {
    await _backend.write(
      '/allowlist/${entry.uid}/disabled',
      disabled,
      idToken: await _session.freshToken(),
    );
    await refresh();
  }

  Future<void> _writeEntry({
    required String uid,
    required String accountId,
    required String username,
    required int generation,
    required String token,
  }) =>
      _backend.write(
        '/allowlist/$uid',
        _entryJson(uid: uid, accountId: accountId, username: username, generation: generation),
        idToken: token,
      );

  Map<String, Object?> _entryJson({
    required String uid,
    required String accountId,
    required String username,
    required int generation,
  }) =>
      AllowlistEntry(
        uid: uid,
        accountId: accountId,
        username: username,
        createdAt: DateTime.now(),
        createdBy: _session.state.uid,
        disabled: false,
        mustChangePassword: true,
        generation: generation,
      ).toJson();

  // --- Codigos de amigo -------------------------------------------------

  /// Rutas que da un codigo a una cuenta: el indice, la copia en la cuenta y
  /// el contador un paso mas alla.
  static Map<String, Object?> _codeWrites(String accountId, int counter, String code) => {
        'friendCodes/$code': accountId,
        'users/$accountId/friendCode': code,
        'system/friendCodeCounter': counter + 1,
      };

  /// Lee el contador, construye la escritura con el codigo que le toca y la
  /// lanza. Si otro admin se ha adelantado, las reglas la rechazan y se
  /// reintenta una vez con el contador nuevo.
  Future<void> _withNextCode(
    String token,
    Map<String, Object?> Function(int counter, String code) paths,
  ) async {
    for (var attempt = 0;; attempt++) {
      final raw = await _backend.read('/system/friendCodeCounter', idToken: token);
      final counter = raw is num ? raw.toInt() : 1;
      try {
        await _backend.merge('/', paths(counter, FriendCode.forCounter(counter)), idToken: token);
        return;
      } on IbashoException catch (e) {
        if (attempt > 0 || e.failure == IbashoFailure.network) rethrow;
      }
    }
  }

  /// Da codigo a las cuentas que se crearon antes de que existieran. Se lanza
  /// solo al abrir el panel; no hace nada si ya lo tienen todas.
  Future<int> assignMissingFriendCodes() async {
    try {
      final token = await _session.freshToken();
      final codes = await _backend.read('/friendCodes', idToken: token);
      final withCode = <String>{
        if (codes is Map)
          for (final value in codes.values)
            if (value is String) value,
      };
      final accounts = <String>{
        for (final entry in state.accounts) entry.accountId,
      }.where((a) => !withCode.contains(a)).toList()
        ..sort();
      for (final account in accounts) {
        await _withNextCode(token, (counter, code) => _codeWrites(account, counter, code));
      }
      return accounts.length;
    } catch (e) {
      debugPrint('Ibasho: no se han podido repartir los codigos de amigo ($e)');
      return 0;
    }
  }
}
