// Ibasho — Ohirune: el puzle de la siesta. Motor sin interfaz.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

/// Los tableros: N×N casillas repartidas en N zonas, una por Tama. Hacen
/// falta tantos Tamas como casillas tiene el lado, así que cada nivel se abre
/// al tener los suyos.
enum OhiruneLevel {
  easy(5),
  normal(6),
  hard(7),
  expert(8),
  master(9);

  const OhiruneLevel(this.size);

  final int size;

  /// Los Tamas que hacen falta para jugarlo.
  int get tamasNeeded => size;
}

/// Tamas con los que se abre el canal: los del nivel fácil.
int get ohiruneUnlockTamas => OhiruneLevel.easy.tamasNeeded;

/// El tablero del día es igual para todo el mundo y va en normal.
const OhiruneLevel ohiruneDailyLevel = OhiruneLevel.normal;

/// Vidas de cada partida.
const int ohiruneLives = 3;

/// Lo que suma cada vida perdida al tiempo del día en la clasificación.
const Duration ohiruneLifePenalty = Duration(seconds: 20);

/// Un puzle: a qué zona pertenece cada casilla y la única solución.
class OhirunePuzzle {
  OhirunePuzzle._(this.size, this.regions, this.solution);

  /// Lado del tablero.
  final int size;

  /// Casilla (`y * size + x`) → zona, de 0 a `size - 1`.
  final List<int> regions;

  /// Fila → columna del Tama que duerme en ella.
  final List<int> solution;

  int regionAt(int x, int y) => regions[y * size + x];

  bool isAnswer(int x, int y) => solution[y] == x;

  /// Genera un puzle de lado [size] con una sola solución. Siempre sale el
  /// mismo con la misma [seed].
  factory OhirunePuzzle.generate(int size, {int? seed}) {
    assert(size >= 4, 'con menos de 4 no caben los Tamas sin tocarse');
    final random = Random(seed);
    for (;;) {
      final solution = _placement(size, random);
      final regions = _grow(size, solution, random);
      if (_disambiguate(size, regions, solution, random)) {
        return OhirunePuzzle._(size, regions, solution);
      }
    }
  }

  /// El del día [day] (`bonusDay()`, día UTC): el mismo para todos.
  factory OhirunePuzzle.daily(int day) => OhirunePuzzle.generate(ohiruneDailyLevel.size, seed: day * 7919 + 0x0417);

  /// Un Tama por fila y columna sin tocarse en diagonal, al azar.
  static List<int> _placement(int n, Random random) {
    final cols = List<int>.filled(n, -1);
    final used = List<bool>.filled(n, false);
    bool place(int row) {
      if (row == n) return true;
      final order = List<int>.generate(n, (i) => i)..shuffle(random);
      for (final c in order) {
        if (used[c]) continue;
        if (row > 0 && (cols[row - 1] - c).abs() <= 1) continue;
        cols[row] = c;
        used[c] = true;
        if (place(row + 1)) return true;
        used[c] = false;
      }
      return false;
    }

    place(0);
    return cols;
  }

  /// Hace crecer una zona desde cada Tama de la solución, casilla a casilla
  /// y a ritmos distintos, hasta cubrir el tablero: salen formas de país.
  static List<int> _grow(int n, List<int> solution, Random random) {
    final regions = List<int>.filled(n * n, -1);
    for (var r = 0; r < n; r++) {
      regions[r * n + solution[r]] = r;
    }
    // Unas zonas comen más deprisa que otras: así no salen todas iguales.
    final appetite = [for (var r = 0; r < n; r++) .35 + random.nextDouble() * 1.3];
    var left = n * n - n;
    while (left > 0) {
      final frontier = <(int, int)>[];
      final weights = <double>[];
      for (var i = 0; i < n * n; i++) {
        if (regions[i] != -1) continue;
        for (final j in _neighbours(n, i)) {
          final r = regions[j];
          if (r == -1) continue;
          frontier.add((i, r));
          weights.add(appetite[r]);
        }
      }
      var pick = random.nextDouble() * weights.fold<double>(0, (a, b) => a + b);
      var k = 0;
      while (k < weights.length - 1 && pick >= weights[k]) {
        pick -= weights[k];
        k++;
      }
      final (cell, region) = frontier[k];
      regions[cell] = region;
      left--;
    }
    return regions;
  }

  /// Retoca las zonas hasta que [solution] sea la única. Cada otra solución
  /// que aparece se rompe pasando a una zona vecina una de sus casillas: esa
  /// zona queda con dos Tamas y la suya con ninguno. Si se atasca, `false` y
  /// se vuelve a empezar.
  static bool _disambiguate(int n, List<int> regions, List<int> solution, Random random) {
    for (var round = 0; round < n * n * 3; round++) {
      final other = solveOhirune(n, regions, avoid: solution);
      if (other == null) return true;
      final rows = [
        for (var y = 0; y < n; y++)
          if (other[y] != solution[y]) y,
      ]..shuffle(random);
      var moved = false;
      for (final y in rows) {
        final cell = y * n + other[y];
        final from = regions[cell];
        final targets = {
          for (final j in _neighbours(n, cell))
            if (regions[j] != from) regions[j],
        }.toList()..shuffle(random);
        if (targets.isEmpty || !_connectedWithout(n, regions, cell)) continue;
        regions[cell] = targets.first;
        moved = true;
        break;
      }
      if (!moved) return false;
    }
    return false;
  }

  /// ¿Sigue unida la zona de [cell] si se la quita?
  static bool _connectedWithout(int n, List<int> regions, int cell) {
    final region = regions[cell];
    final members = [
      for (var i = 0; i < n * n; i++)
        if (regions[i] == region && i != cell) i,
    ];
    if (members.isEmpty) return false;
    final seen = <int>{members.first};
    final queue = [members.first];
    while (queue.isNotEmpty) {
      final i = queue.removeLast();
      for (final j in _neighbours(n, i)) {
        if (j != cell && regions[j] == region && seen.add(j)) queue.add(j);
      }
    }
    return seen.length == members.length;
  }
}

/// Vecinas en cruz de la casilla [i] de un tablero de lado [n].
Iterable<int> _neighbours(int n, int i) sync* {
  final x = i % n, y = i ~/ n;
  if (x > 0) yield i - 1;
  if (x < n - 1) yield i + 1;
  if (y > 0) yield i - n;
  if (y < n - 1) yield i + n;
}

/// Busca una solución de las zonas [regions] (fila → columna), distinta de
/// [avoid] si se da. `null` si no hay.
List<int>? solveOhirune(int n, List<int> regions, {List<int>? avoid}) {
  final cols = List<int>.filled(n, -1);
  var colUsed = 0, regionUsed = 0;
  List<int>? found;
  bool go(int row) {
    if (row == n) {
      if (avoid != null && _same(cols, avoid)) return false;
      found = List<int>.of(cols);
      return true;
    }
    for (var c = 0; c < n; c++) {
      if (colUsed & (1 << c) != 0) continue;
      if (row > 0 && (cols[row - 1] - c).abs() <= 1) continue;
      final r = regions[row * n + c];
      if (regionUsed & (1 << r) != 0) continue;
      cols[row] = c;
      colUsed |= 1 << c;
      regionUsed |= 1 << r;
      if (go(row + 1)) return true;
      colUsed &= ~(1 << c);
      regionUsed &= ~(1 << r);
    }
    return false;
  }

  go(0);
  return found;
}

bool _same(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Lo que hay en una casilla.
enum OhiruneMark { none, cross, tama }

enum OhiruneStatus { ready, playing, won, lost }

/// Qué ha pasado al poner un Tama.
enum OhirunePlace {
  /// Ahí no se podía (ya hay algo, o la partida ha acabado).
  ignored,

  /// Se ha dormido en su sitio.
  placed,

  /// No era su sitio: una vida menos, y la casilla queda con una X.
  miss,
}

/// Qué reglas rompe un Tama puesto en una casilla, y con qué Tamas.
class OhiruneClash {
  const OhiruneClash({
    required this.row,
    required this.column,
    required this.zone,
    required this.touching,
    required this.culprits,
  });

  final bool row;
  final bool column;
  final bool zone;

  /// Toca a otro Tama, también en diagonal.
  final bool touching;

  /// Casillas de los Tamas con los que choca.
  final Set<int> culprits;

  bool get any => row || column || zone || touching;
}

/// Una partida: el puzle, las marcas y las vidas.
class OhiruneGame {
  OhiruneGame(this.puzzle) : marks = List<OhiruneMark>.filled(puzzle.size * puzzle.size, OhiruneMark.none);

  final OhirunePuzzle puzzle;
  final List<OhiruneMark> marks;
  int lives = ohiruneLives;
  OhiruneStatus status = OhiruneStatus.ready;

  int get size => puzzle.size;
  bool get isOver => status == OhiruneStatus.won || status == OhiruneStatus.lost;
  int get livesLost => ohiruneLives - lives;
  int get tamasPlaced => marks.where((m) => m == OhiruneMark.tama).length;

  OhiruneMark markAt(int x, int y) => marks[y * size + x];

  /// Pone un Tama en ([x], [y]). Una X se quita primero: poner el Tama
  /// encima no cuesta nada.
  OhirunePlace place(int x, int y) {
    if (isOver || markAt(x, y) != OhiruneMark.none) return OhirunePlace.ignored;
    status = OhiruneStatus.playing;
    final i = y * size + x;
    if (!puzzle.isAnswer(x, y)) {
      marks[i] = OhiruneMark.cross;
      misses.add(i);
      lives--;
      if (lives <= 0) status = OhiruneStatus.lost;
      return OhirunePlace.miss;
    }
    marks[i] = OhiruneMark.tama;
    if (tamasPlaced == size) status = OhiruneStatus.won;
    return OhirunePlace.placed;
  }

  /// Casillas de los fallos: su X es roja y no se puede quitar.
  final Set<int> misses = <int>{};

  /// Las reglas que rompería un Tama en ([x], [y]) con los que ya duermen.
  /// Puede no romper ninguna a la vista y aun así no ser su sitio.
  OhiruneClash clashAt(int x, int y) {
    final n = size;
    final zone = puzzle.regionAt(x, y);
    final culprits = <int>{};
    var row = false, column = false, sameZone = false, touching = false;
    for (var i = 0; i < n * n; i++) {
      if (marks[i] != OhiruneMark.tama) continue;
      final tx = i % n, ty = i ~/ n;
      if (tx == x && ty == y) continue;
      var hit = false;
      if (ty == y) row = hit = true;
      if (tx == x) column = hit = true;
      if (puzzle.regions[i] == zone) sameZone = hit = true;
      if ((tx - x).abs() <= 1 && (ty - y).abs() <= 1) touching = hit = true;
      if (hit) culprits.add(i);
    }
    return OhiruneClash(row: row, column: column, zone: sameZone, touching: touching, culprits: culprits);
  }

  /// Las casillas que se iluminan por [clash] de un fallo en ([x], [y]): la
  /// fila, la columna, la zona o el cuadro de 3×3 de alrededor.
  Set<int> clashArea(int x, int y, OhiruneClash clash) {
    final n = size;
    final zone = puzzle.regionAt(x, y);
    return {
      for (var i = 0; i < n * n; i++)
        if ((clash.row && i ~/ n == y) ||
            (clash.column && i % n == x) ||
            (clash.zone && puzzle.regions[i] == zone) ||
            (clash.touching && (i % n - x).abs() <= 1 && (i ~/ n - y).abs() <= 1))
          i,
    };
  }

  /// Pone o quita una X. Nunca cuesta vidas.
  void toggleCross(int x, int y) => setCross(x, y, markAt(x, y) != OhiruneMark.cross);

  /// Deja la X puesta ([on]) o quitada, al arrastrar por varias casillas.
  void setCross(int x, int y, bool on) {
    if (isOver) return;
    final i = y * size + x;
    if (marks[i] == OhiruneMark.tama || misses.contains(i)) return;
    if (status == OhiruneStatus.ready) status = OhiruneStatus.playing;
    marks[i] = on ? OhiruneMark.cross : OhiruneMark.none;
  }
}
