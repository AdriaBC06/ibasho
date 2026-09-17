// Ibasho — claves de identidad para el cifrado de punta a punta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';


import 'package:flutter/foundation.dart';
// pointycastle trae su propia PublicKey, que aqui solo estorba.
import 'package:pointycastle/export.dart' hide PrivateKey, PublicKey;

import 'random.dart';

/// La curva de todo el cifrado de Ibasho: NIST P-256.
///
/// No es la que se elegiria hoy desde cero —X25519 es mas limpia— pero
/// pointycastle 4 no la trae, y toda la red de Ibasho es Dart puro porque los
/// plugins de FlutterFire no soportan Linux. P-256 con ECDH esta en la misma
/// familia de seguridad (128 bits) y es lo que hay disponible sin meter una
/// dependencia nativa en tres plataformas.
ECDomainParameters get ibashoCurve => ECCurve_secp256r1();

/// Longitud en bytes de una coordenada de la curva.
const int _coordinateBytes = 32;

/// Una clave publica ajena, tal y como viaja por la base.
///
/// Se guarda el punto sin comprimir (`04 || X || Y`, 65 bytes) en base64. Sin
/// comprimir a proposito: descomprimir exige una raiz cuadrada modular y no
/// merece la pena ahorrar 32 bytes en un nodo que se lee una vez.
@immutable
class PublicKey {
  const PublicKey._(this.point, this.encoded);

  /// El punto de la curva.
  final ECPoint point;

  /// `04 || X || Y` en base64: lo que hay en `/users/{acc}/keys/pub`.
  final String encoded;

  /// `null` si no es un punto valido de la curva. Nunca lanza: lo que llega de
  /// la base es dato ajeno y el que lo manda puede tener la app parcheada.
  static PublicKey? tryParse(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final bytes = base64.decode(raw);
      if (bytes.length != 1 + _coordinateBytes * 2 || bytes[0] != 0x04) {
        return null;
      }
      final point = ibashoCurve.curve.decodePoint(bytes);
      if (point == null || point.isInfinity) return null;
      // decodePoint no comprueba que el punto este en la curva en todas las
      // implementaciones: multiplicarlo por el cofactor lo confirma.
      if ((point * ibashoCurve.n)?.isInfinity != true) return null;
      return PublicKey._(point, raw);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is PublicKey && other.encoded == encoded;

  @override
  int get hashCode => encoded.hashCode;

  @override
  String toString() => 'PublicKey(${encoded.substring(0, 12)}…)';
}

/// El par de claves de una cuenta. La privada no sale nunca de aqui en claro:
/// se guarda en el llavero del sistema y, envuelta con la frase de respaldo,
/// en la base.
@immutable
class IdentityKeys {
  const IdentityKeys({required this.private, required this.public});

  /// El escalar privado.
  final BigInt private;

  final PublicKey public;

  /// Un par nuevo.
  static IdentityKeys generate() {
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(ibashoCurve),
          seededRandom(),
        ),
      );
    final pair = generator.generateKeyPair();
    final private = pair.privateKey.d!;
    return IdentityKeys(private: private, public: _publicFrom(private));
  }

  /// Reconstruye el par desde los 32 bytes de la privada.
  static IdentityKeys? fromPrivateBytes(Uint8List bytes) {
    if (bytes.length != _coordinateBytes) return null;
    final d = _toBigInt(bytes);
    if (d <= BigInt.zero || d >= ibashoCurve.n) return null;
    return IdentityKeys(private: d, public: _publicFrom(d));
  }

  /// Los 32 bytes de la privada, para envolverla o guardarla en el llavero.
  Uint8List get privateBytes => _toBytes(private, _coordinateBytes);

  /// El secreto compartido con `other`: la coordenada X del punto ECDH.
  ///
  /// Sale en crudo a proposito; quien lo use tiene que pasarlo por un HKDF
  /// antes de cifrar nada con el (lo hace `envelope.dart`).
  Uint8List sharedSecret(PublicKey other) {
    final agreement = ECDHBasicAgreement()
      ..init(ECPrivateKey(private, ibashoCurve));
    final x = agreement.calculateAgreement(ECPublicKey(other.point, ibashoCurve));
    return _toBytes(x, _coordinateBytes);
  }

  static PublicKey _publicFrom(BigInt d) {
    final q = (ibashoCurve.G * d)!;
    return PublicKey._(q, base64.encode(q.getEncoded(false)));
  }
}

/// Entero sin signo a bytes big-endian de largo fijo.
Uint8List _toBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  return out;
}

BigInt _toBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}
