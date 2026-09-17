// Ibasho — modelo de la mensajeria cifrada.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../crypto/envelope.dart';
import 'tama.dart';

/// Largo maximo de un mensaje de texto.
const int messageTextMax = 500;

/// Cuantos mensajes se guardan por conversacion. Al pasarse, quien escribe
/// borra los mas viejos en la misma operacion.
const int messagesPerConversation = 300;

/// Y cuanto vive un mensaje, se llegue o no al tope.
const Duration messageLifetime = Duration(days: 90);

/// Miembros como mucho en un grupo: es el techo del sobre, porque cada mensaje
/// se envuelve una vez por cada uno.
const int maxGroupMembers = maxEnvelopeRecipients;

/// El grupo que trae Ibasho de serie. No se pueden crear grupos: solo unirse.
const String globalGroupId = 'global';

/// Que lleva dentro un mensaje.
enum MessageKind {
  text,
  sticker;

  static MessageKind byName(Object? raw) =>
      values.firstWhere((k) => k.name == raw, orElse: () => MessageKind.text);
}

/// Las caras de un sticker.
///
/// Son poses, no dibujos: cada una se traduce a un `TamaPose` y se pinta con
/// el mismo pintor que el Tama de la habitacion. Por eso un sticker sale con
/// el cuerpo, el color y las orejas del Tama que elijas, y no hay ni un solo
/// mapa de bits que descargar.
enum StickerFace {
  happy,
  wink,
  surprised,
  angry,
  love,
  sad,
  sleepy,
  wave;

  static StickerFace byName(Object? raw) =>
      values.firstWhere((f) => f.name == raw, orElse: () => StickerFace.happy);
}

/// El contenido en claro de un mensaje: lo que se cifra y lo que sale al
/// descifrar. Nunca se guarda asi en ninguna parte.
@immutable
sealed class MessageBody {
  const MessageBody();

  MessageKind get kind;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// `null` si el texto descifrado no tiene la forma esperada: puede venir de
  /// una version posterior de la app, y entonces se enseña como "no se puede
  /// mostrar" en vez de reventar la conversacion.
  static MessageBody? decode(String plaintext) {
    try {
      final raw = jsonDecode(plaintext);
      if (raw is! Map) return null;
      return switch (raw['t']) {
        'text' => TextBody.fromJson(raw),
        'sticker' => StickerBody.fromJson(raw),
        _ => null,
      };
    } catch (e) {
      debugPrint('Ibasho: mensaje descifrado pero ilegible ($e)');
      return null;
    }
  }
}

/// Texto pelado.
@immutable
class TextBody extends MessageBody {
  const TextBody(this.text);

  final String text;

  @override
  MessageKind get kind => MessageKind.text;

  static TextBody? fromJson(Map raw) {
    final text = raw['b'];
    if (text is! String || text.isEmpty || text.length > messageTextMax) {
      return null;
    }
    return TextBody(text);
  }

  @override
  Map<String, Object?> toJson() => {'t': 'text', 'b': text};
}

/// Un Tama con una cara.
///
/// El aspecto viaja entero dentro del sobre en vez de por referencia, y es a
/// proposito: quien lo recibe no tiene permiso para leer ese Tama en la base
/// (solo el de perfil es publico), y ademas asi el sticker se sigue viendo
/// igual dentro de un año, aunque el Tama se haya editado o borrado.
@immutable
class StickerBody extends MessageBody {
  const StickerBody({required this.face, required this.name, required this.look});

  final StickerFace face;

  /// El nombre del Tama, para el pie del sticker.
  final String name;

  final TamaLook look;

  @override
  MessageKind get kind => MessageKind.sticker;

  static StickerBody? fromJson(Map raw) {
    final name = raw['n'];
    final look = raw['l'];
    if (name is! String || name.isEmpty || name.length > 16) return null;
    if (look is! Map) return null;
    return StickerBody(
      face: StickerFace.byName(raw['f']),
      name: name,
      look: TamaLook.fromJson(look),
    );
  }

  @override
  Map<String, Object?> toJson() => {
        't': 'sticker',
        'f': face.name,
        'n': name,
        'l': look.toJson(),
      };
}

/// Un mensaje ya abierto (o que no se ha podido abrir).
@immutable
class Message {
  const Message({
    required this.id,
    required this.at,
    required this.from,
    required this.kind,
    this.body,
  });

  /// Id de push: ordena por tiempo sin mirar `at`.
  final String id;

  final DateTime at;

  /// accountId de quien lo mando.
  final String from;

  /// Lo que dice el sobre por fuera. Si no cuadra con `body` es que el sobre
  /// esta tocado; la pantalla se fia de `body`.
  final MessageKind kind;

  /// `null` si el sobre no iba dirigido a esta cuenta, esta corrupto o viene
  /// de una version que no entendemos. La conversacion lo enseña como un hueco
  /// y sigue adelante.
  final MessageBody? body;

  bool get readable => body != null;

  @override
  bool operator ==(Object other) => other is Message && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Un sobre tal cual esta en la base, sin abrir.
@immutable
class StoredMessage {
  const StoredMessage({
    required this.id,
    required this.at,
    required this.from,
    required this.kind,
    required this.envelope,
  });

  final String id;
  final DateTime at;
  final String from;
  final MessageKind kind;
  final SealedEnvelope envelope;

  static StoredMessage? fromJson(String id, Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    final from = raw['from'];
    final envelope = SealedEnvelope.fromJson(raw);
    if (at is! num || from is! String || envelope == null) return null;
    return StoredMessage(
      id: id,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      from: from,
      kind: MessageKind.byName(raw['kind']),
      envelope: envelope,
    );
  }
}

/// El id de una conversacion privada: los dos accountId ordenados, unidos por
/// un guion bajo. Las reglas comprueban que cuadre con `a` y `b`, asi que la
/// misma pareja no puede acabar hablando en dos sitios distintos.
String directPairId(String one, String other) {
  final ends = directPairEnds(one, other);
  return '${ends.a}_${ends.b}';
}

/// Las dos mitades de un `pairId`, en el orden en que van a `a` y `b`.
({String a, String b}) directPairEnds(String one, String other) {
  final a = one.compareTo(other) <= 0 ? one : other;
  final b = a == one ? other : one;
  return (a: a, b: b);
}

/// Un aviso de `/users/{acc}/inbox/{from}`: de quien y cuando, nada mas.
@immutable
class InboxEntry {
  const InboxEntry({required this.accountId, required this.at});

  final String accountId;
  final DateTime at;

  static InboxEntry? fromJson(String accountId, Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    return InboxEntry(
      accountId: accountId,
      at: DateTime.fromMillisecondsSinceEpoch((raw['at'] as num).toInt()),
    );
  }
}

/// Un miembro de un grupo, con su clave publica ya a mano.
@immutable
class GroupMember {
  const GroupMember({required this.accountId, required this.at, required this.pub});

  final String accountId;
  final DateTime at;

  /// La publica copiada al entrar. Las reglas la obligan a coincidir con la de
  /// su cuenta; esta aqui para poder cifrar sin leer 32 arboles ajenos.
  final String pub;

  static GroupMember? fromJson(String accountId, Object? raw) {
    if (raw is! Map || raw['pub'] is! String) return null;
    final at = raw['at'];
    return GroupMember(
      accountId: accountId,
      at: DateTime.fromMillisecondsSinceEpoch(at is num ? at.toInt() : 0),
      pub: raw['pub'] as String,
    );
  }
}

/// La ficha de un grupo: lo unico que se ve sin estar dentro.
@immutable
class GroupInfo {
  const GroupInfo({
    required this.id,
    required this.name,
    required this.open,
    required this.createdAt,
  });

  final String id;
  final String name;

  /// Si se puede entrar sin que nadie te invite.
  final bool open;

  final DateTime createdAt;

  static GroupInfo? fromJson(String id, Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    final created = raw['createdAt'];
    return GroupInfo(
      id: id,
      name: raw['name'] as String,
      open: raw['open'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created is num ? created.toInt() : 0),
    );
  }
}
