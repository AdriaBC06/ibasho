// Ibasho — las claves de cifrado de la cuenta en curso.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import '../crypto/backup.dart';
import '../crypto/keys.dart';
import '../crypto/mnemonic.dart';
import '../storage/secure_store.dart';
import 'session.dart';

/// En que punto esta el cifrado de esta cuenta en este aparato.
enum IdentityPhase {
  /// Mirando el llavero y la base.
  loading,

  /// Todo en su sitio: se puede leer y escribir.
  ready,

  /// Claves recien creadas. Hay que enseñar la frase una vez y que la persona
  /// diga que la ha apuntado; hasta entonces no se da por hecha.
  fresh,

  /// La cuenta tiene claves, pero este aparato no. Hacen falta las doce
  /// palabras. Es lo que pasa al entrar desde el movil por primera vez.
  needsPhrase,

  /// No se ha podido averiguar (sin red, o la lectura fallo). Se reintenta.
  unavailable,
}

@immutable
class IdentityState {
  const IdentityState({
    this.phase = IdentityPhase.loading,
    this.keys,
    this.phrase = const <String>[],
    this.restoreFailed = false,
  });

  final IdentityPhase phase;

  /// Las claves de esta cuenta. `null` mientras no esten.
  final IdentityKeys? keys;

  /// Las doce palabras, si este aparato las conoce: o las genero el, o se
  /// tecleron aqui para recuperar. Se guardan en el llavero, al lado de la
  /// clave privada y con la misma proteccion, para poder volver a enseñarlas
  /// desde Ajustes. Del respaldo de la base no se pueden sacar.
  final List<String> phrase;

  /// El ultimo intento de recuperar con una frase no abrio el respaldo.
  final bool restoreFailed;

  bool get usable => keys != null && phase != IdentityPhase.loading;

  IdentityState copyWith({
    IdentityPhase? phase,
    IdentityKeys? keys,
    List<String>? phrase,
    bool? restoreFailed,
  }) =>
      IdentityState(
        phase: phase ?? this.phase,
        keys: keys ?? this.keys,
        phrase: phrase ?? this.phrase,
        restoreFailed: restoreFailed ?? this.restoreFailed,
      );
}

/// Trae las claves de la cuenta a este aparato, o las crea si no las hay.
///
/// El orden importa y no es obvio:
///
/// 1. Se lee `/users/{cuenta}/keys` y el llavero del sistema.
/// 2. Si el llavero tiene una privada cuya publica es la que hay en la base,
///    listo: ese es el caso de todos los arranques menos el primero.
/// 3. Si la base tiene claves y el llavero no —movil nuevo, reinstalacion—,
///    hacen falta las doce palabras.
/// 4. Si no hay claves en ninguna parte, se crean aqui, se envuelven con una
///    frase nueva y se publica la publica. La frase se enseña una sola vez.
///
/// Si el llavero tiene una privada que **no** cuadra con la base, gana la base:
/// alguien recupero la cuenta en otro aparato y genero claves nuevas, y lo de
/// aqui ya no sirve para descifrar lo que llegue a partir de ahora.
class IdentityController extends StateNotifier<IdentityState> {
  IdentityController({
    required IbashoBackend backend,
    required SessionController session,
    required SecureStore store,
  })  : _backend = backend,
        _session = session,
        _store = store,
        super(const IdentityState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final SecureStore _store;

  String get _me => _session.state.accountId;

  String get _privateKeyName => 'ibasho.identity.$_me';

  String get _phraseKeyName => 'ibasho.phrase.$_me';

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final remote = await _backend.read('/users/$_me/keys', idToken: token);
      final published = remote is Map ? remote['pub'] : null;
      final backup = KeyBackup.fromJson(remote is Map ? remote['backup'] : null);

      final stored = await _store.read(_privateKeyName);
      final local = stored == null
          ? null
          : IdentityKeys.fromPrivateBytes(base64.decode(stored));

      if (local != null && local.public.encoded == published) {
        if (!mounted) return;
        state = IdentityState(
          phase: IdentityPhase.ready,
          keys: local,
          phrase: await _readPhrase(),
        );
        return;
      }

      if (published is String || backup != null) {
        // La cuenta ya tiene claves y este aparato no las tiene (o tiene unas
        // viejas). Solo la frase las trae de vuelta.
        await _store.delete(_privateKeyName);
        await _store.delete(_phraseKeyName);
        if (!mounted) return;
        state = const IdentityState(phase: IdentityPhase.needsPhrase);
        return;
      }

      await _create(token);
    } catch (e) {
      debugPrint('Ibasho: no se han podido preparar las claves ($e)');
      if (mounted) state = const IdentityState(phase: IdentityPhase.unavailable);
    }
  }

  /// Primera vez: claves nuevas, frase nueva y publicacion.
  Future<void> _create(String token) async {
    final keys = IdentityKeys.generate();
    final phrase = generateMnemonic();
    final backup = KeyBackup.wrap(keys, phrase);

    await _backend.write(
      '/users/$_me/keys',
      <String, Object?>{
        'pub': keys.public.encoded,
        'backup': backup.toJson(),
        'at': serverTimestamp,
      },
      idToken: token,
    );
    await _remember(keys, phrase);
    if (!mounted) return;
    state = IdentityState(phase: IdentityPhase.fresh, keys: keys, phrase: phrase);
  }

  /// La persona dice que ya ha apuntado la frase.
  void confirmPhraseSeen() {
    if (state.phase == IdentityPhase.fresh) {
      state = state.copyWith(phase: IdentityPhase.ready);
    }
  }

  /// Recupera las claves con las doce palabras.
  ///
  /// Devuelve `null` si sale bien, o el fallo de la frase si esta mal escrita.
  /// Que la frase sea correcta pero no abra el respaldo se cuenta aparte, con
  /// `restoreFailed`: es el caso de teclear la frase de otra cuenta.
  Future<MnemonicError?> restoreWithPhrase(String typed) async {
    state = state.copyWith(restoreFailed: false);
    final List<String> words;
    try {
      entropyFromMnemonic(typed);
      words = normalizeMnemonic(typed);
    } on MnemonicError catch (e) {
      return e;
    }

    try {
      final token = await _session.freshToken();
      final remote = await _backend.read('/users/$_me/keys', idToken: token);
      final backup = KeyBackup.fromJson(remote is Map ? remote['backup'] : null);
      final keys = backup?.unwrap(words);
      final published = remote is Map ? remote['pub'] : null;

      if (keys == null || keys.public.encoded != published) {
        if (mounted) state = state.copyWith(restoreFailed: true);
        return null;
      }

      await _remember(keys, words);
      if (mounted) {
        state = IdentityState(
          phase: IdentityPhase.ready,
          keys: keys,
          phrase: words,
        );
      }
    } catch (e) {
      debugPrint('Ibasho: la recuperacion no ha llegado al servidor ($e)');
      if (mounted) state = state.copyWith(restoreFailed: true);
    }
    return null;
  }

  /// Quien ha perdido las doce palabras empieza de cero: claves nuevas, frase
  /// nueva y respaldo nuevo, encima de los de antes. Los mensajes viejos
  /// quedan cerrados para siempre en este lado (iban a la clave anterior, y
  /// sin la frase nadie puede abrirla); los amigos siguen leyendo su copia.
  /// Las reglas ya dejan a la dueña reescribir `/users/{cuenta}/keys`.
  Future<bool> startOver() async {
    try {
      await _store.delete(_privateKeyName);
      await _store.delete(_phraseKeyName);
      await _create(await _session.freshToken());
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se han podido crear claves nuevas ($e)');
      return false;
    }
  }

  /// Vuelve a intentar el arranque tras un fallo de red.
  Future<void> retry() async {
    if (!mounted) return;
    state = const IdentityState();
    await _start();
  }

  /// La clave publica de otra cuenta. `null` si esa persona todavia no ha
  /// entrado desde que existe el cifrado: no se le puede mandar nada.
  Future<PublicKey?> publicKeyOf(String accountId) async {
    try {
      final token = await _session.freshToken();
      final raw = await _backend.read('/users/$accountId/keys/pub', idToken: token);
      return PublicKey.tryParse(raw);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer la clave de $accountId ($e)');
      return null;
    }
  }

  Future<void> _remember(IdentityKeys keys, List<String> phrase) async {
    await _store.write(_privateKeyName, base64.encode(keys.privateBytes));
    await _store.write(_phraseKeyName, phrase.join(' '));
  }

  Future<List<String>> _readPhrase() async {
    final raw = await _store.read(_phraseKeyName);
    return raw == null ? const <String>[] : normalizeMnemonic(raw);
  }
}
