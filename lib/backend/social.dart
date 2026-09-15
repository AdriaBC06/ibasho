// Ibasho — modelo de datos de amigos, presencia y muro.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../theme/tokens.dart';
import 'tama.dart';

/// Cuantos amigos puede tener una cuenta. Las reglas lo aplican con
/// `/users/{accountId}/friendCount`; la app lo usa para avisar antes.
const int maxFriendsPerAccount = 100;

/// Largo maximo de un mensaje del muro de cumpleaños.
const int wallMessageMax = 140;

/// `/users/{accountId}/card`: la ficha reducida que ve quien aun no es amigo.
@immutable
class UserCard {
  const UserCard({
    required this.displayName,
    this.accentColor = '#5BC8F5',
    this.tamaId,
  });

  final String displayName;

  /// `#RRGGBB`: el acento efectivo de la persona, siga o no a su Tama.
  final String accentColor;

  /// El Tama de perfil. Es el unico Tama ajeno que las reglas dejan pintar.
  final String? tamaId;

  Color get accent => colorFromHex(accentColor) ?? T.cyan;

  static UserCard? fromJson(Object? raw) {
    if (raw is! Map || raw['displayName'] is! String) return null;
    return UserCard(
      displayName: raw['displayName'] as String,
      accentColor: raw['accentColor'] is String ? raw['accentColor'] as String : '#5BC8F5',
      tamaId: raw['tamaId'] as String?,
    );
  }

  Map<String, Object?> toJson() => {
        'displayName': displayName,
        'accentColor': accentColor,
        'tamaId': ?tamaId,
      };

  @override
  bool operator ==(Object other) =>
      other is UserCard &&
      other.displayName == displayName &&
      other.accentColor.toUpperCase() == accentColor.toUpperCase() &&
      other.tamaId == tamaId;

  @override
  int get hashCode => Object.hash(displayName, accentColor.toUpperCase(), tamaId);
}

/// Estado que elige la persona. Se guarda en `/users/{accountId}/presenceMode`,
/// que solo lee ella.
enum PresenceMode {
  /// Conectado; pasa a ausente solo tras un rato sin tocar nada.
  online,

  /// Ausente fijado a mano.
  away,

  /// No molestar.
  busy,

  /// Para los demas, exactamente igual que desconectado.
  invisible;

  static PresenceMode byName(Object? raw) =>
      values.firstWhere((m) => m.name == raw, orElse: () => PresenceMode.online);
}

/// Estado publicado en `/users/{accountId}/presence`, el que ven los amigos.
/// No tiene `invisible` a proposito.
enum PresenceState {
  online,
  away,
  busy,
  offline;

  static PresenceState byName(Object? raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => PresenceState.offline);
}

/// `/users/{accountId}/presence`.
@immutable
class Presence {
  const Presence({required this.state, this.lastSeen});

  static const Presence offline = Presence(state: PresenceState.offline);

  final PresenceState state;
  final DateTime? lastSeen;

  static Presence fromJson(Object? raw) {
    if (raw is! Map) return offline;
    final seen = raw['lastSeen'];
    return Presence(
      state: PresenceState.byName(raw['state']),
      lastSeen: seen is num ? DateTime.fromMillisecondsSinceEpoch(seen.toInt()) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Presence && other.state == state && other.lastSeen == lastSeen;

  @override
  int get hashCode => Object.hash(state, lastSeen);
}

/// Una entrada de `/users/{accountId}/friends`.
@immutable
class Friendship {
  const Friendship({required this.accountId, required this.since});

  final String accountId;
  final DateTime since;
}

/// Una entrada de `/users/{accountId}/requests/in` u `out`.
@immutable
class FriendRequest {
  const FriendRequest({required this.accountId, required this.at});

  final String accountId;
  final DateTime at;
}

/// Un mensaje de `/users/{accountId}/wall/{year}/{author}`.
@immutable
class WallMessage {
  const WallMessage({
    required this.year,
    required this.author,
    required this.text,
    required this.at,
  });

  final int year;
  final String author;
  final String text;
  final DateTime at;
}

DateTime _at(Object? raw) =>
    DateTime.fromMillisecondsSinceEpoch(raw is Map && raw['at'] is num
        ? (raw['at'] as num).toInt()
        : raw is Map && raw['since'] is num
            ? (raw['since'] as num).toInt()
            : 0);

List<Friendship> parseFriends(Object? raw) {
  if (raw is! Map) return const <Friendship>[];
  final list = [
    for (final e in raw.entries) Friendship(accountId: '${e.key}', since: _at(e.value)),
  ]..sort((a, b) => a.since.compareTo(b.since));
  return List<Friendship>.unmodifiable(list);
}

List<FriendRequest> parseRequests(Object? raw) {
  if (raw is! Map) return const <FriendRequest>[];
  final list = [
    for (final e in raw.entries) FriendRequest(accountId: '${e.key}', at: _at(e.value)),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return List<FriendRequest>.unmodifiable(list);
}

/// El muro entero, del año mas reciente al mas antiguo y, dentro de cada año,
/// del mensaje mas antiguo al mas nuevo.
Map<int, List<WallMessage>> parseWall(Object? raw) {
  if (raw is! Map) return const <int, List<WallMessage>>{};
  final years = <int, List<WallMessage>>{};
  raw.forEach((yearKey, messages) {
    final year = int.tryParse('$yearKey');
    if (year == null || messages is! Map) return;
    final list = <WallMessage>[
      for (final e in messages.entries)
        if (e.value is Map && (e.value as Map)['text'] is String)
          WallMessage(
            year: year,
            author: '${e.key}',
            text: (e.value as Map)['text'] as String,
            at: _at(e.value),
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    if (list.isNotEmpty) years[year] = list;
  });
  final sorted = years.keys.toList()..sort((a, b) => b.compareTo(a));
  return {for (final y in sorted) y: years[y]!};
}
