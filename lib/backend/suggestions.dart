// Ibasho — modelo del buzon de sugerencias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Largos de una sugerencia. Cortos a proposito: obligan a decir la idea en
/// una linea, y hacen que la lista del panel de administracion se lea entera
/// de un vistazo.
const int suggestionTitleMax = 30;
const int suggestionBodyMax = 200;

/// Largo del motivo que puede dejar el admin al decidir.
const int suggestionNoteMax = 140;

/// En que estado esta la sugerencia de una cuenta.
enum SuggestionStatus {
  /// Mandada y sin responder. Mientras este asi, esa cuenta no puede mandar
  /// otra: lo aplican las reglas, no solo la pantalla.
  pending,

  accepted,
  rejected;

  static SuggestionStatus byName(Object? raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => SuggestionStatus.pending);
}

/// `/suggestions/{accountId}`: la ultima sugerencia de una cuenta.
@immutable
class Suggestion {
  const Suggestion({
    required this.accountId,
    required this.title,
    required this.body,
    required this.at,
    required this.status,
    this.note,
    this.decidedAt,
    this.decidedBy,
  });

  final String accountId;
  final String title;
  final String body;
  final DateTime at;
  final SuggestionStatus status;

  /// Lo que escribio el admin al decidir, si escribio algo.
  final String? note;

  final DateTime? decidedAt;

  /// Nombre visible de quien decidio.
  final String? decidedBy;

  bool get isPending => status == SuggestionStatus.pending;

  static Suggestion? fromJson(String accountId, Object? raw) {
    if (raw is! Map || raw['title'] is! String || raw['body'] is! String) {
      return null;
    }
    final at = raw['at'];
    if (at is! num) return null;
    final decidedAt = raw['decidedAt'];
    return Suggestion(
      accountId: accountId,
      title: raw['title'] as String,
      body: raw['body'] as String,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      status: SuggestionStatus.byName(raw['status']),
      note: raw['note'] is String && (raw['note'] as String).isNotEmpty
          ? raw['note'] as String
          : null,
      decidedAt: decidedAt is num
          ? DateTime.fromMillisecondsSinceEpoch(decidedAt.toInt())
          : null,
      decidedBy: raw['decidedBy'] is String ? raw['decidedBy'] as String : null,
    );
  }
}

/// Una sugerencia aceptada, en la lista publica del canal. Lleva el nombre de
/// quien la propuso, no su accountId: es una lista para leer.
@immutable
class AcceptedSuggestion {
  const AcceptedSuggestion({
    required this.id,
    required this.title,
    required this.by,
    required this.at,
  });

  final String id;
  final String title;
  final String by;
  final DateTime at;

  static AcceptedSuggestion? fromJson(String id, Object? raw) {
    if (raw is! Map || raw['title'] is! String || raw['by'] is! String) {
      return null;
    }
    final at = raw['at'];
    if (at is! num) return null;
    return AcceptedSuggestion(
      id: id,
      title: raw['title'] as String,
      by: raw['by'] as String,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
    );
  }

  @override
  bool operator ==(Object other) => other is AcceptedSuggestion && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
