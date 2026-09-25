// Ibasho — Odori: récords por version, dificultad y teclas, y las opciones
// del juego (direccion, aspecto, velocidad, desfase, teclas, tema y Tama).
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../game_store.dart';
import 'odori_board.dart';
import 'odori_chart.dart';
import 'odori_engine.dart';
import 'odori_hits.dart';
import 'odori_keys.dart';

/// El mejor resultado de una combinacion.
@immutable
class OdoriBest {
  const OdoriBest({
    required this.score,
    required this.rank,
    required this.accuracy,
    required this.misses,
    required this.maxCombo,
    this.plays = 1,
  });

  final int score;
  final OdoriRank rank;
  final double accuracy;
  final int misses;
  final int maxCombo;
  final int plays;

  static OdoriBest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw.cast<String, Object?>();
    final rank = OdoriRank.values.where((r) => r.name == j['rank']).firstOrNull;
    if (rank == null) return null;
    return OdoriBest(
      score: readInt(j['score']),
      rank: rank,
      accuracy: (j['accuracy'] as num?)?.toDouble() ?? 0,
      misses: readInt(j['misses']),
      maxCombo: readInt(j['maxCombo']),
      plays: math.max(1, readInt(j['plays'])),
    );
  }

  /// El mejor de los dos, con las partidas de ambos.
  static OdoriBest merge(OdoriBest a, OdoriBest b) {
    final top = b.score > a.score ? b : a;
    return OdoriBest(
      score: top.score,
      rank: top.rank,
      accuracy: top.accuracy,
      misses: top.misses,
      maxCombo: top.maxCombo,
      plays: a.plays + b.plays,
    );
  }

  Map<String, Object?> toJson() => {
        'score': score,
        'rank': rank.name,
        'accuracy': accuracy,
        'misses': misses,
        'maxCombo': maxCombo,
        'plays': plays,
      };
}

/// Los dos modos: Taki, carriles de 1 a 7 teclas, y Butai, el escenario
/// con 4.
enum OdoriMode { taki, butai }

/// Lo que lleva cada burbuja de Butai: su flecha, su figura (□ ✕ △ ○, como
/// en los mandos) o la tecla que la toca.
enum ButaiMark { arrows, shapes, keys }

/// Como se juega Butai con los dedos: tocando la diana donde cae cada nota,
/// o con cuatro botones abajo.
enum ButaiTouch { targets, pad }

/// Clave de un récord: por canción, nunca por versión (instrumental, idioma o
/// voz dan el mismo récord). Butai lleva sus propios récords en vez de un
/// numero de teclas, y las partidas con la ayuda del Tama van aparte.
String odoriRecordKey(
  String songId,
  OdoriDifficulty difficulty,
  int keys, {
  bool assisted = false,
  OdoriMode mode = OdoriMode.taki,
}) =>
    '$songId|${difficulty.name}|${mode == OdoriMode.butai ? 'butai' : keys}${assisted ? '|tama' : ''}';

/// Lo que se recuerda entre partidas.
@immutable
class OdoriPrefs {
  const OdoriPrefs({
    this.songId,
    this.versionId,
    this.difficulty = OdoriDifficulty.normal,
    this.keys = 4,
    this.mode = OdoriMode.taki,
    this.butaiMark = ButaiMark.arrows,
    this.butaiTouch = ButaiTouch.targets,
    this.hitVolume = odoriHitDefault,
    this.butaiDouble = false,
    this.butaiAlt = butaiAltDefault,
    this.flow = TakiFlow.down,
    this.look = NoteLook.circle,
    this.approach = 1.2,
    this.offsetMs = 0,
    this.themeId,
    this.tamaId,
    this.assist = false,
    this.keyMaps = const <int, List<PhysicalKeyboardKey>>{},
  });

  final String? songId;
  final String? versionId;
  final OdoriDifficulty difficulty;
  final int keys;
  final OdoriMode mode;

  /// Lo que se dibuja en las burbujas de Butai.
  final ButaiMark butaiMark;

  /// Como se toca Butai en una pantalla tactil.
  final ButaiTouch butaiTouch;

  /// Volumen de los soniditos de cada toque; 0, sin ellos.
  final double hitVolume;

  /// Si cada figura de Butai tiene ademas una segunda tecla, [butaiAlt].
  final bool butaiDouble;
  final List<PhysicalKeyboardKey> butaiAlt;
  final TakiFlow flow;
  final NoteLook look;

  /// Segundos que tarda una nota en llegar al receptor.
  final double approach;

  /// Desfase calibrado: positivo si el audio llega tarde.
  final int offsetMs;

  /// Fondo del tema del juego; `null` sigue al del menu.
  final String? themeId;

  /// Tama que acompaña; `null`, el que toque.
  final String? tamaId;

  /// Si la ayuda del Tama esta puesta.
  final bool assist;

  /// Teclas cambiadas por numero de carriles. Lo que no este, por defecto.
  final Map<int, List<PhysicalKeyboardKey>> keyMaps;

  List<PhysicalKeyboardKey> keysFor(int n) => keyMaps[n] ?? odoriDefaultKeys[n]!;

  static const double minApproach = .5;
  static const double maxApproach = 2.4;
  static const int maxOffset = 300;

  OdoriPrefs copyWith({
    String? songId,
    String? versionId,
    OdoriDifficulty? difficulty,
    int? keys,
    OdoriMode? mode,
    ButaiMark? butaiMark,
    ButaiTouch? butaiTouch,
    double? hitVolume,
    bool? butaiDouble,
    List<PhysicalKeyboardKey>? butaiAlt,
    TakiFlow? flow,
    NoteLook? look,
    double? approach,
    int? offsetMs,
    String? Function()? themeId,
    String? Function()? tamaId,
    bool? assist,
    Map<int, List<PhysicalKeyboardKey>>? keyMaps,
  }) =>
      OdoriPrefs(
        songId: songId ?? this.songId,
        versionId: versionId ?? this.versionId,
        difficulty: difficulty ?? this.difficulty,
        keys: keys ?? this.keys,
        mode: mode ?? this.mode,
        butaiMark: butaiMark ?? this.butaiMark,
        butaiTouch: butaiTouch ?? this.butaiTouch,
        hitVolume: hitVolume ?? this.hitVolume,
        butaiDouble: butaiDouble ?? this.butaiDouble,
        butaiAlt: butaiAlt ?? this.butaiAlt,
        flow: flow ?? this.flow,
        look: look ?? this.look,
        approach: approach ?? this.approach,
        offsetMs: offsetMs ?? this.offsetMs,
        themeId: themeId != null ? themeId() : this.themeId,
        tamaId: tamaId != null ? tamaId() : this.tamaId,
        assist: assist ?? this.assist,
        keyMaps: keyMaps ?? this.keyMaps,
      );

  static T _byName<T extends Enum>(List<T> values, Object? raw, T fallback) =>
      values.where((v) => v.name == raw).firstOrNull ?? fallback;

  static OdoriPrefs fromJson(Object? raw) {
    if (raw is! Map) return const OdoriPrefs();
    final j = raw.cast<String, Object?>();
    final maps = <int, List<PhysicalKeyboardKey>>{};
    final rawMaps = j['keyMaps'];
    if (rawMaps is Map) {
      for (final e in rawMaps.entries) {
        final n = int.tryParse('${e.key}');
        final list = e.value;
        if (n == null || list is! List || list.length != n) continue;
        maps[n] = [for (final k in list) PhysicalKeyboardKey(readInt(k))];
      }
    }
    final rawAlt = j['butaiAlt'];
    return OdoriPrefs(
      songId: j['songId'] as String?,
      versionId: j['versionId'] as String?,
      difficulty: _byName(OdoriDifficulty.values, j['difficulty'], OdoriDifficulty.normal),
      keys: readInt(j['keys']).clamp(odoriMinKeys, odoriMaxKeys),
      mode: _byName(OdoriMode.values, j['mode'], OdoriMode.taki),
      butaiMark: _byName(ButaiMark.values, j['butaiMark'], ButaiMark.arrows),
      butaiTouch: _byName(ButaiTouch.values, j['butaiTouch'], ButaiTouch.targets),
      hitVolume: ((j['hitLevel'] as num?)?.toDouble() ?? odoriHitDefault).clamp(0.0, odoriHitMax),
      butaiDouble: j['butaiDouble'] == true,
      butaiAlt: rawAlt is List && rawAlt.length == 4
          ? [for (final k in rawAlt) PhysicalKeyboardKey(readInt(k))]
          : butaiAltDefault,
      flow: _byName(TakiFlow.values, j['flow'], TakiFlow.down),
      look: _byName(NoteLook.values, j['look'], NoteLook.circle),
      approach: ((j['approach'] as num?)?.toDouble() ?? 1.2).clamp(minApproach, maxApproach),
      offsetMs: readInt(j['offsetMs']).clamp(-maxOffset, maxOffset),
      themeId: j['themeId'] as String?,
      tamaId: j['tamaId'] as String?,
      assist: j['assist'] == true,
      keyMaps: maps,
    );
  }

  Map<String, Object?> toJson() => {
        'songId': songId,
        'versionId': versionId,
        'difficulty': difficulty.name,
        'keys': keys,
        'mode': mode.name,
        'butaiMark': butaiMark.name,
        'butaiTouch': butaiTouch.name,
        'hitLevel': hitVolume,
        'butaiDouble': butaiDouble,
        'butaiAlt': [for (final k in butaiAlt) k.usbHidUsage],
        'flow': flow.name,
        'look': look.name,
        'approach': approach,
        'offsetMs': offsetMs,
        'themeId': themeId,
        'tamaId': tamaId,
        'assist': assist,
        'keyMaps': {
          for (final e in keyMaps.entries) '${e.key}': [for (final k in e.value) k.usbHidUsage],
        },
      };
}

/// Todo lo de Odori en `odori.json`: opciones y récords.
class OdoriData {
  OdoriData({this.prefs = const OdoriPrefs(), Map<String, OdoriBest>? records})
      : records = records ?? <String, OdoriBest>{};

  OdoriPrefs prefs;
  final Map<String, OdoriBest> records;

  static OdoriData fromJson(Map<String, Object?> j) {
    final records = <String, OdoriBest>{};
    final raw = j['records'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final best = OdoriBest.fromJson(e.value);
        if (best == null) continue;
        // Los récords de antes iban por versión (`yako_ja_teto|…`): se juntan
        // en los de su canción, con el mejor y todas las partidas.
        final parts = '${e.key}'.split('|');
        parts[0] = parts[0].split('_').first;
        final key = parts.join('|');
        final had = records[key];
        records[key] = had == null ? best : OdoriBest.merge(had, best);
      }
    }
    return OdoriData(prefs: OdoriPrefs.fromJson(j['prefs']), records: records);
  }

  Map<String, Object?> toJson() => {
        'prefs': prefs.toJson(),
        'records': {for (final e in records.entries) e.key: e.value.toJson()},
      };

  /// Apunta [result] y dice si es récord nuevo (la primera partida no lo es:
  /// no habia nada que batir). Devuelve tambien el récord anterior.
  (bool, OdoriBest?) record(String key, OdoriResult result) {
    final old = records[key];
    final better = old == null || result.score > old.score;
    final plays = (old?.plays ?? 0) + 1;
    records[key] = better
        ? OdoriBest(
            score: result.score,
            rank: result.rank,
            accuracy: result.accuracy,
            misses: result.misses,
            maxCombo: result.maxCombo,
            plays: plays,
          )
        : OdoriBest(
            score: old.score,
            rank: old.rank,
            accuracy: old.accuracy,
            misses: old.misses,
            maxCombo: old.maxCombo,
            plays: plays,
          );
    return (old != null && better, old);
  }

  /// El récord de una canción en una dificultad, con [keys] teclas o en
  /// Butai.
  OdoriBest? bestOf(
    String songId,
    OdoriDifficulty difficulty,
    int keys, {
    bool assisted = false,
    OdoriMode mode = OdoriMode.taki,
  }) =>
      records[odoriRecordKey(songId, difficulty, keys, assisted: assisted, mode: mode)];
}

/// Donde se guarda.
class OdoriStore {
  OdoriStore._(this._store, this.data);

  final GameStore _store;
  final OdoriData data;

  static Future<OdoriStore> open() async {
    final store = await GameStore.open('odori');
    return OdoriStore._(store, OdoriData.fromJson(await store.load()));
  }

  Future<void> save() => _store.save(data.toJson());
}
