// Ibasho — el cifrado, fuera del hilo que pinta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'envelope.dart';
import 'keys.dart';

/// Abrir un sobre cuesta una multiplicacion escalar sobre la curva: unos 9 ms
/// en un portatil y bastante mas en un movil. Una conversacion llena son 300,
/// o sea casi tres segundos, y hacerlo aqui congelaria la pantalla entera.
///
/// Por eso todo lo caro pasa por un isolate. Lo que cruza son solo bytes y
/// mapas —nada de `IdentityKeys`, que lleva puntos de la curva y no viaja— y
/// la clave privada se reconstruye al otro lado.
///
/// La conversacion ademas pide los mensajes de los nuevos a los viejos y en
/// tandas, para que lo primero que se ve aparezca enseguida y el resto vaya
/// llegando mientras se sube.
abstract final class CryptoWorker {
  /// Abre una tanda de sobres. Devuelve el texto en claro de cada uno, en el
  /// mismo orden, con `null` donde no se haya podido.
  static Future<List<String?>> open({
    required List<Map<String, Object?>> envelopes,
    required String account,
    required Uint8List privateKey,
  }) {
    if (envelopes.isEmpty) return Future.value(const <String?>[]);
    return Isolate.run(
      () => _openBatch((envelopes: envelopes, account: account, privateKey: privateKey)),
      debugName: 'ibasho.abrir',
    );
  }

  /// Cierra un sobre para varios destinatarios.
  ///
  /// Con 32 miembros son casi 200 ms: poco para una espera, demasiado para un
  /// fotograma.
  static Future<Map<String, Object?>> seal({
    required String plaintext,
    required Map<String, String> recipients,
  }) =>
      Isolate.run(
        () => _sealOne((plaintext: plaintext, recipients: recipients)),
        debugName: 'ibasho.cerrar',
      );
}

typedef _OpenJob = ({
  List<Map<String, Object?>> envelopes,
  String account,
  Uint8List privateKey,
});

List<String?> _openBatch(_OpenJob job) {
  final keys = IdentityKeys.fromPrivateBytes(job.privateKey);
  if (keys == null) {
    return List<String?>.filled(job.envelopes.length, null);
  }
  return <String?>[
    for (final raw in job.envelopes)
      SealedEnvelope.fromJson(raw)?.open(job.account, keys),
  ];
}

typedef _SealJob = ({String plaintext, Map<String, String> recipients});

Map<String, Object?> _sealOne(_SealJob job) {
  final recipients = <String, PublicKey>{};
  for (final entry in job.recipients.entries) {
    final key = PublicKey.tryParse(entry.value);
    if (key != null) recipients[entry.key] = key;
  }
  return SealedEnvelope.seal(job.plaintext, recipients: recipients).toJson();
}
