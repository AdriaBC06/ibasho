// Ibasho — modelo del canal de noticias y sus encuestas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Largos de una entrada. Los mismos que comprueban las reglas.
const int newsTitleMax = 60;
const int newsBodyMax = 600;
const int pollOptionMax = 40;

/// Cuantas opciones puede tener una encuesta. Dos para poder preguntar si o
/// no, cuatro porque mas no caben de un vistazo en la composicion vertical.
const int pollOptionsMin = 2;
const int pollOptionsMax = 4;

/// Que clase de entrada es.
enum NewsKind {
  /// Una version nueva y lo que trae.
  update,

  /// Un aviso suelto.
  note,

  /// Una encuesta.
  poll;

  static NewsKind byName(Object? raw) =>
      values.firstWhere((k) => k.name == raw, orElse: () => NewsKind.note);
}

/// Una entrada del tablon.
///
/// El recuento (`tally`) y la lista de quien ha votado (`voters`) viven en la
/// entrada; a que voto cada cual, no. Eso esta solo en el arbol de quien vota,
/// que no lee nadie mas, y por eso la encuesta es anonima de verdad y no solo
/// en la pantalla.
@immutable
class NewsItem {
  const NewsItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.at,
    required this.by,
    this.body = '',
    this.version,
    this.options = const <String>[],
    this.tally = const <int>[],
    this.voters = 0,
    this.closesAt,
    this.closed = false,
  });

  final String id;
  final NewsKind kind;
  final String title;
  final String body;

  /// La version que anuncia, si es una novedad de version.
  final String? version;

  final DateTime at;

  /// Nombre visible de quien la publico.
  final String by;

  /// Opciones de la encuesta, en orden.
  final List<String> options;

  /// Votos por opcion, alineado con `options`.
  final List<int> tally;

  /// Cuanta gente ha votado. Sirve para no enseñar porcentajes sobre cero.
  final int voters;

  /// Cuando se cierra sola. `null` en las que se cierran a mano.
  final DateTime? closesAt;

  /// Cerrada a mano por el admin.
  final bool closed;

  bool get isPoll => kind == NewsKind.poll && options.length >= pollOptionsMin;

  /// Si todavia se puede votar.
  bool isOpenAt(DateTime now) =>
      isPoll && !closed && (closesAt == null || closesAt!.isAfter(now));

  int get totalVotes => tally.fold(0, (sum, n) => sum + n);

  /// Porcentaje de una opcion, de 0 a 1. Cero si aun no ha votado nadie.
  double share(int option) {
    final total = totalVotes;
    if (total <= 0 || option < 0 || option >= tally.length) return 0;
    return tally[option] / total;
  }

  static NewsItem? fromJson(String id, Object? raw) {
    if (raw is! Map || raw['title'] is! String) return null;
    final at = raw['at'];
    if (at is! num) return null;

    final rawOptions = raw['options'];
    final options = <String>[];
    if (rawOptions is Map) {
      for (var i = 0; i < pollOptionsMax; i++) {
        final value = rawOptions['$i'];
        if (value is String) options.add(value);
      }
    } else if (rawOptions is List) {
      for (final value in rawOptions) {
        if (value is String) options.add(value);
      }
    }

    final rawTally = raw['tally'];
    final tally = <int>[
      for (var i = 0; i < options.length; i++)
        switch (rawTally) {
          final Map m when m['$i'] is num => (m['$i'] as num).toInt(),
          final List l when i < l.length && l[i] is num => (l[i] as num).toInt(),
          _ => 0,
        },
    ];

    final rawVoters = raw['voters'];
    final closesAt = raw['closesAt'];

    return NewsItem(
      id: id,
      kind: NewsKind.byName(raw['kind']),
      title: raw['title'] as String,
      body: raw['body'] is String ? raw['body'] as String : '',
      version: raw['version'] is String ? raw['version'] as String : null,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      by: raw['by'] is String ? raw['by'] as String : '',
      options: List<String>.unmodifiable(options),
      tally: List<int>.unmodifiable(tally),
      voters: rawVoters is Map ? rawVoters.length : 0,
      closesAt: closesAt is num
          ? DateTime.fromMillisecondsSinceEpoch(closesAt.toInt())
          : null,
      closed: raw['closed'] == true,
    );
  }

  @override
  bool operator ==(Object other) => other is NewsItem && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
