// Ibasho — el sobre cifrado que viaja por la base.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
// pointycastle trae su propia PublicKey, que aqui solo estorba.
import 'package:pointycastle/export.dart' hide PrivateKey, PublicKey;

import 'keys.dart';
import 'random.dart';

/// Cuantos destinatarios caben en un sobre.
///
/// Cada uno anade 60 bytes de envoltorio, asi que el limite es de tamano, no
/// de seguridad. Tambien es el techo de miembros de un grupo: en el Global,
/// cada mensaje se cifra una vez por cada miembro.
const int maxEnvelopeRecipients = 32;

/// Etiqueta de version del formato. Va dentro del HKDF, de modo que un sobre
/// de otra version no se abre por accidente ni a medias.
const String _info = 'ibasho.envelope.v1';

const int _nonceBytes = 12;
const int _keyBytes = 32;
const int _macBits = 128;

/// Un mensaje cifrado, tal cual se guarda en la base.
///
/// Solo el texto va cifrado una vez; la clave que lo abre se envuelve una vez
/// por destinatario. Asi un mensaje de grupo no se cifra N veces entero, y
/// quien no esta en `wraps` no tiene por donde empezar: ni el dueño de la base
/// de datos, que ve exactamente esto y nada mas.
///
/// ```
/// { "e": "<punto efimero>",
///   "c": "<nonce||texto cifrado||mac>",
///   "k": { "<accountId>": "<nonce||clave envuelta||mac>", … } }
/// ```
@immutable
class SealedEnvelope {
  const SealedEnvelope({
    required this.ephemeral,
    required this.ciphertext,
    required this.wraps,
  });

  /// Clave publica efimera del sobre: una por mensaje, nunca reutilizada.
  final String ephemeral;

  /// Texto cifrado en base64, con su nonce delante y su MAC detras.
  final String ciphertext;

  /// accountId → clave del mensaje envuelta para esa persona.
  final Map<String, String> wraps;

  /// Quienes pueden abrirlo. No es secreto: la base ya ve las claves de `k`.
  Iterable<String> get recipients => wraps.keys;

  /// Cierra `plaintext` para `recipients`.
  ///
  /// Quien envia tiene que ir en `recipients` o no podra releer lo que acaba
  /// de mandar: la clave efimera se tira en cuanto sale de aqui, que es
  /// justamente lo que da el secreto hacia adelante.
  static SealedEnvelope seal(
    String plaintext, {
    required Map<String, PublicKey> recipients,
  }) {
    if (recipients.isEmpty) {
      throw ArgumentError('Un sobre sin destinatarios no lo abriria nadie');
    }
    if (recipients.length > maxEnvelopeRecipients) {
      throw ArgumentError('Como mucho $maxEnvelopeRecipients destinatarios');
    }

    final ephemeral = IdentityKeys.generate();
    final messageKey = randomBytes(_keyBytes);

    final wraps = <String, String>{};
    for (final entry in recipients.entries) {
      final wrapKey = _deriveWrapKey(
        shared: ephemeral.sharedSecret(entry.value),
        ephemeral: ephemeral.public.encoded,
        account: entry.key,
      );
      wraps[entry.key] = _encrypt(wrapKey, messageKey);
    }

    return SealedEnvelope(
      ephemeral: ephemeral.public.encoded,
      ciphertext: _encrypt(messageKey, Uint8List.fromList(utf8.encode(plaintext))),
      wraps: wraps,
    );
  }

  /// Abre el sobre con las claves de `account`, o `null` si no va dirigido a
  /// esa cuenta, esta manipulado o viene de una version que no entendemos.
  ///
  /// Nunca lanza: un solo mensaje corrupto en una conversacion no puede tirar
  /// la pantalla entera.
  String? open(String account, IdentityKeys keys) {
    final wrapped = wraps[account];
    if (wrapped == null) return null;
    final ephemeralKey = PublicKey.tryParse(ephemeral);
    if (ephemeralKey == null) return null;
    try {
      final wrapKey = _deriveWrapKey(
        shared: keys.sharedSecret(ephemeralKey),
        ephemeral: ephemeral,
        account: account,
      );
      final messageKey = _decrypt(wrapKey, wrapped);
      if (messageKey == null || messageKey.length != _keyBytes) return null;
      final plain = _decrypt(messageKey, ciphertext);
      return plain == null ? null : utf8.decode(plain);
    } catch (e) {
      debugPrint('Ibasho: sobre ilegible ($e)');
      return null;
    }
  }

  static SealedEnvelope? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final ephemeral = raw['e'];
    final ciphertext = raw['c'];
    final wraps = raw['k'];
    if (ephemeral is! String || ciphertext is! String || wraps is! Map) {
      return null;
    }
    return SealedEnvelope(
      ephemeral: ephemeral,
      ciphertext: ciphertext,
      wraps: <String, String>{
        for (final e in wraps.entries)
          if (e.value is String) '${e.key}': e.value as String,
      },
    );
  }

  Map<String, Object?> toJson() => {
        'e': ephemeral,
        'c': ciphertext,
        'k': wraps,
      };
}

/// HKDF-SHA256 sobre el secreto ECDH.
///
/// El punto efimero entra como sal y el destinatario como informacion, asi que
/// cada envoltorio tiene su propia clave aunque el secreto compartido se
/// repita: sin esto, dos mensajes al mismo amigo reutilizarian clave.
Uint8List _deriveWrapKey({
  required Uint8List shared,
  required String ephemeral,
  required String account,
}) {
  final kdf = HKDFKeyDerivator(SHA256Digest())
    ..init(
      HkdfParameters(
        shared,
        _keyBytes,
        Uint8List.fromList(utf8.encode(ephemeral)),
        Uint8List.fromList(utf8.encode('$_info|$account')),
      ),
    );
  return kdf.process(Uint8List(0));
}

GCMBlockCipher _cipher(Uint8List key, Uint8List nonce, {required bool encrypt}) =>
    GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)),
      );

/// `nonce || texto cifrado || mac`, en base64.
String _encrypt(Uint8List key, Uint8List plain) {
  final nonce = randomBytes(_nonceBytes);
  final body = _cipher(key, nonce, encrypt: true).process(plain);
  return base64.encode(<int>[...nonce, ...body]);
}

Uint8List? _decrypt(Uint8List key, String encoded) {
  final raw = base64.decode(encoded);
  if (raw.length <= _nonceBytes + _macBits ~/ 8) return null;
  final nonce = Uint8List.sublistView(raw, 0, _nonceBytes);
  final body = Uint8List.sublistView(raw, _nonceBytes);
  // Si el MAC no cuadra, process lanza: el sobre esta tocado.
  return _cipher(key, nonce, encrypt: false).process(body);
}
