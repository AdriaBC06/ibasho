// Ibasho — la clave privada envuelta con la frase de respaldo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
// pointycastle trae su propia PublicKey, que aqui solo estorba.
import 'package:pointycastle/export.dart' hide PrivateKey, PublicKey;

import 'keys.dart';
import 'mnemonic.dart';
import 'random.dart';

/// Lo que se guarda en `/users/{accountId}/keys/backup`: la clave privada de
/// identidad cifrada con una clave que solo sale de las doce palabras.
///
/// Es lo unico que hace que el historial sobreviva a cambiar de movil o a que
/// un administrador resetee la contraseña: la contraseña no interviene aqui
/// para nada. Quien tenga la base entera ve este blob y la sal, y sin la frase
/// no puede hacer nada con ellos.
///
/// ```
/// { "v": 1, "s": "<sal>", "d": "<nonce||privada cifrada||mac>" }
/// ```
@immutable
class KeyBackup {
  const KeyBackup({required this.salt, required this.data});

  final String salt;
  final String data;

  static const int _version = 1;
  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _macBits = 128;

  /// Envuelve `keys` con `phrase`.
  static KeyBackup wrap(IdentityKeys keys, List<String> phrase) {
    final salt = randomBytes(_saltBytes);
    final wrapKey = _deriveKey(phrase, salt);
    final nonce = randomBytes(_nonceBytes);
    final body = _cipher(wrapKey, nonce, encrypt: true).process(keys.privateBytes);
    return KeyBackup(
      salt: base64.encode(salt),
      data: base64.encode(<int>[...nonce, ...body]),
    );
  }

  /// Recupera las claves, o `null` si la frase no es la de este respaldo.
  ///
  /// No distingue entre frase equivocada y respaldo tocado a proposito, y es
  /// deliberado: el MAC de GCM falla igual en los dos casos y no hay nada util
  /// que contarle a quien lo intenta.
  IdentityKeys? unwrap(List<String> phrase) {
    try {
      final raw = base64.decode(data);
      if (raw.length <= _nonceBytes) return null;
      final wrapKey = _deriveKey(phrase, base64.decode(salt));
      final nonce = Uint8List.sublistView(raw, 0, _nonceBytes);
      final body = Uint8List.sublistView(raw, _nonceBytes);
      final plain = _cipher(wrapKey, nonce, encrypt: false).process(body);
      return IdentityKeys.fromPrivateBytes(plain);
    } catch (e) {
      debugPrint('Ibasho: el respaldo no se ha abierto con esa frase ($e)');
      return null;
    }
  }

  static KeyBackup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final salt = raw['s'];
    final data = raw['d'];
    if (salt is! String || data is! String) return null;
    if (raw['v'] != _version) return null;
    return KeyBackup(salt: salt, data: data);
  }

  Map<String, Object?> toJson() => {'v': _version, 's': salt, 'd': data};
}

/// Argon2id sobre la frase.
///
/// La frase ya trae 104 bits de azar, asi que el coste del derivado no es lo
/// que la protege de la fuerza bruta: nadie recorre 2^104. Se pone de todos
/// modos, y con memoria de sobra, porque encarece el unico ataque que si tiene
/// sentido —una frase copiada a medias o adivinada en parte— y porque 32 MiB
/// los aguanta hasta el movil mas modesto sin que se note en el arranque.
Uint8List _deriveKey(List<String> phrase, Uint8List salt) {
  final material = phrase.map(normalizeWord).join(' ');
  final argon2 = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: 3,
        memoryPowerOf2: 15,
        lanes: 1,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
  return argon2.process(Uint8List.fromList(utf8.encode(material)));
}

GCMBlockCipher _cipher(Uint8List key, Uint8List nonce, {required bool encrypt}) =>
    GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(
          KeyParameter(key),
          KeyBackup._macBits,
          nonce,
          Uint8List(0),
        ),
      );
