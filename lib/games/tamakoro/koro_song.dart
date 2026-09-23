// Ibasho — una cancion de Tamakoro: la partitura pintada en el lienzo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Pasos del lienzo, de izquierda a derecha. Cada uno es una corchea.
const int koroSteps = 32;

/// Notas del lienzo, de abajo arriba.
const int koroRows = 16;

/// Tamas que caben en el coro.
const int koroSeats = 6;

/// Huecos de canciones que trae toda cuenta.
const int koroFreeSlots = 10;

/// Tope de huecos, comprando en el Yatai.
const int koroMaxSlots = 50;

/// Tempo, en pulsaciones por minuto. Las reglas exigen lo mismo.
const int koroMinTempo = 60;
const int koroMaxTempo = 180;
const int koroDefaultTempo = 120;

/// Precio del proximo hueco segun cuantos hay ya: 10 monedas del 11 al 20,
/// 20 del 21 al 30, y asi. El articulo del Yatai es `koro_slot_{tramo}`.
int koroSlotTier(int slots) => ((slots - koroFreeSlots) ~/ 10) + 1;

/// La escala sobre la que caen las filas: el trazo es libre, pero la tinta
/// siempre afina.
enum KoroScale {
  major([0, 2, 4, 5, 7, 9, 11], 60),
  minor([0, 2, 3, 5, 7, 8, 10], 57),
  penta([0, 2, 4, 7, 9], 48);

  const KoroScale(this.steps, this.root);

  /// Semitonos de cada grado dentro de la octava.
  final List<int> steps;

  /// Nota MIDI de la fila de abajo. La pentatonica empieza mas grave porque
  /// con cinco grados sus dieciseis filas suben tres octavas.
  final int root;

  /// Nota MIDI de [row] (0 es la de abajo).
  int midiOf(int row) =>
      root + 12 * (row ~/ steps.length) + steps[row % steps.length];

  static KoroScale byName(Object? raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => KoroScale.major);
}

/// Frecuencia de una nota MIDI.
double koroHz(num midi) => 440.0 * math.pow(2, (midi - 69) / 12).toDouble();

/// Una nota ya resuelta: un Tama que canta una fila durante unos pasos
/// seguidos. La tinta contigua en la misma fila se liga en una sola nota.
@immutable
class KoroNote {
  const KoroNote({required this.seat, required this.row, required this.start, required this.length});

  final int seat;
  final int row;
  final int start;
  final int length;
}

/// Una cancion. Vive en `/users/{cuenta}/koro/songs/{hueco}` y solo la lee su
/// dueña: no se comparte.
@immutable
class KoroSong {
  KoroSong({
    required this.number,
    Uint8List? cells,
    List<String?>? seats,
    this.scale = KoroScale.major,
    this.tempo = koroDefaultTempo,
  })  : cells = cells ?? Uint8List(koroSteps * koroRows),
        seats = List<String?>.unmodifiable(seats ?? List<String?>.filled(koroSeats, null));

  /// El numero del titulo («Graznata n.º 3»). No se edita.
  final int number;

  /// Una celda por paso y fila (`paso * koroRows + fila`): 0 si no hay tinta,
  /// o el asiento del coro (1 a 6) cuya tinta es.
  final Uint8List cells;

  /// El Tama sentado en cada asiento del coro, por id. `null`: vacio.
  final List<String?> seats;

  final KoroScale scale;
  final int tempo;

  static int index(int step, int row) => step * koroRows + row;

  int at(int step, int row) => cells[index(step, row)];

  bool get isBlank => !cells.any((c) => c != 0);

  /// Segundos que dura un paso: una corchea al tempo de la cancion.
  double get stepSeconds => 30 / tempo;

  double get loopSeconds => stepSeconds * koroSteps;

  /// Las notas, ligando la tinta contigua de un mismo asiento en una fila.
  List<KoroNote> get notes {
    final out = <KoroNote>[];
    for (var row = 0; row < koroRows; row++) {
      var step = 0;
      while (step < koroSteps) {
        final seat = at(step, row);
        if (seat == 0) {
          step++;
          continue;
        }
        var end = step + 1;
        while (end < koroSteps && at(end, row) == seat) {
          end++;
        }
        out.add(KoroNote(seat: seat - 1, row: row, start: step, length: end - step));
        step = end;
      }
    }
    return out;
  }

  KoroSong copyWith({
    Uint8List? cells,
    List<String?>? seats,
    KoroScale? scale,
    int? tempo,
  }) =>
      KoroSong(
        number: number,
        cells: cells ?? this.cells,
        seats: seats ?? this.seats,
        scale: scale ?? this.scale,
        tempo: tempo ?? this.tempo,
      );

  Map<String, Object?> toJson() => {
        'n': number,
        'cells': String.fromCharCodes(cells.map((c) => 0x30 + c)),
        'seats': {
          for (var i = 0; i < koroSeats; i++)
            if (seats[i] != null) '$i': seats[i],
        },
        'scale': scale.name,
        'tempo': tempo,
      };

  static KoroSong? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final n = raw['n'];
    final text = raw['cells'];
    if (n is! num || text is! String || text.length != koroSteps * koroRows) return null;
    final cells = Uint8List(koroSteps * koroRows);
    for (var i = 0; i < cells.length; i++) {
      final c = text.codeUnitAt(i) - 0x30;
      cells[i] = c >= 0 && c <= koroSeats ? c : 0;
    }
    final seats = List<String?>.filled(koroSeats, null);
    final rawSeats = raw['seats'];
    // La base convierte un mapa de claves 0..n en lista: vale cualquiera.
    if (rawSeats is Map) {
      rawSeats.forEach((k, v) {
        final i = int.tryParse('$k');
        if (i != null && i >= 0 && i < koroSeats && v is String) seats[i] = v;
      });
    } else if (rawSeats is List) {
      for (var i = 0; i < rawSeats.length && i < koroSeats; i++) {
        if (rawSeats[i] is String) seats[i] = rawSeats[i] as String;
      }
    }
    final tempo = raw['tempo'];
    return KoroSong(
      number: n.toInt(),
      cells: cells,
      seats: seats,
      scale: KoroScale.byName(raw['scale']),
      tempo: tempo is num ? tempo.toInt().clamp(koroMinTempo, koroMaxTempo) : koroDefaultTempo,
    );
  }
}
