// Ibasho — la logica de Tsumiki, los bloques que caen: sin Flutter.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

/// Las siete piezas, y la casilla gris de las filas que manda el otro en el
/// versus (esa nunca cae: solo sube desde abajo).
enum TsumikiPiece {
  i,
  o,
  t,
  s,
  z,
  j,
  l,
  garbage;

  /// Las que salen de la bolsa.
  static const List<TsumikiPiece> playable = [i, o, t, s, z, j, l];

  /// Una letra por casilla, para mandar el tablero por la red.
  String get code => this == garbage ? 'g' : name;

  static TsumikiPiece? fromCode(String c) => c == 'g'
      ? garbage
      : c == '.'
          ? null
          : TsumikiPiece.values.firstWhere((p) => p.name == c, orElse: () => garbage);
}

enum TsumikiStatus { ready, playing, paused, over }

/// Lo que pasa al asentarse una pieza: sirve para puntuar, para los efectos
/// y para que el Tama reaccione.
class LockEvent {
  const LockEvent({
    required this.cells,
    required this.rows,
    required this.points,
    required this.combo,
    required this.backToBack,
    required this.levelUp,
    required this.gameOver,
    this.garbageIn = 0,
  });

  /// Casillas (`y * ancho + x`) donde se ha quedado la pieza.
  final List<int> cells;

  /// Filas completas que se van a borrar.
  final List<int> rows;
  final int points;

  /// Asentamientos seguidos borrando filas (0 si este no borra, 1 el primero).
  final int combo;

  /// Dos tsumikis (cuatro filas de golpe) seguidos.
  final bool backToBack;
  final bool levelUp;
  final bool gameOver;

  /// Filas grises que han subido al asentarse (versus).
  final int garbageIn;
}

/// La pieza que cae.
class FallingPiece {
  const FallingPiece(this.type, this.rotation, this.x, this.y);

  final TsumikiPiece type;
  final int rotation;
  final int x;
  final int y;

  FallingPiece moved(int dx, int dy, [int? rotation]) =>
      FallingPiece(type, rotation ?? this.rotation, x + dx, y + dy);

  Iterable<(int, int)> get cells sync* {
    for (final (cx, cy) in shapeOf(type, rotation)) {
      yield (x + cx, y + cy);
    }
  }
}

/// Casillas de una pieza en su caja, girada [rotation] cuartos a la derecha.
List<(int, int)> shapeOf(TsumikiPiece type, int rotation) {
  final base = _shapes[type]!;
  final n = _box(type);
  var cells = base;
  for (var r = 0; r < rotation % 4; r++) {
    cells = [for (final (x, y) in cells) (n - 1 - y, x)];
  }
  return cells;
}

int _box(TsumikiPiece type) => switch (type) {
      TsumikiPiece.i => 4,
      TsumikiPiece.o => 2,
      _ => 3,
    };

const Map<TsumikiPiece, List<(int, int)>> _shapes = {
  TsumikiPiece.i: [(0, 1), (1, 1), (2, 1), (3, 1)],
  TsumikiPiece.o: [(0, 0), (1, 0), (0, 1), (1, 1)],
  TsumikiPiece.t: [(1, 0), (0, 1), (1, 1), (2, 1)],
  TsumikiPiece.s: [(1, 0), (2, 0), (0, 1), (1, 1)],
  TsumikiPiece.z: [(0, 0), (1, 0), (1, 1), (2, 1)],
  TsumikiPiece.j: [(0, 0), (0, 1), (1, 1), (2, 1)],
  TsumikiPiece.l: [(2, 0), (0, 1), (1, 1), (2, 1)],
};

// Empujes del giro (SRS). Van con la y hacia arriba, como en la tabla
// original; al probarlos se le da la vuelta.
const Map<int, List<(int, int)>> _kicksJlstz = {
  01: [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
  10: [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
  12: [(0, 0), (1, 0), (1, -1), (0, 2), (1, 2)],
  21: [(0, 0), (-1, 0), (-1, 1), (0, -2), (-1, -2)],
  23: [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
  32: [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
  30: [(0, 0), (-1, 0), (-1, -1), (0, 2), (-1, 2)],
  03: [(0, 0), (1, 0), (1, 1), (0, -2), (1, -2)],
};

const Map<int, List<(int, int)>> _kicksI = {
  01: [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
  10: [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
  12: [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
  21: [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
  23: [(0, 0), (2, 0), (-1, 0), (2, 1), (-1, -2)],
  32: [(0, 0), (-2, 0), (1, 0), (-2, -1), (1, 2)],
  30: [(0, 0), (1, 0), (-2, 0), (1, -2), (-2, 1)],
  03: [(0, 0), (-1, 0), (2, 0), (-1, 2), (2, -1)],
};

/// Puntos por filas borradas de una vez, antes de multiplicar por el nivel.
const List<int> linePoints = [0, 100, 300, 500, 800];

class TsumikiGame {
  TsumikiGame({int? seed, this.startLevel = 1}) : _random = math.Random(seed) {
    _refill();
    _refill();
  }

  static const int width = 10;
  static const int visibleRows = 20;

  /// Filas de mas por encima, donde nacen las piezas.
  static const int hiddenRows = 2;
  static const int rows = visibleRows + hiddenRows;

  /// Tiempo en el suelo antes de asentarse, y cuantas veces se puede
  /// estirar moviendo o girando.
  static const double lockDelay = .5;
  static const int lockResets = 15;

  /// Lo que dura el destello de las filas antes de desaparecer.
  static const double clearDelay = .36;

  /// Filas grises que suben como mucho de una vez; el resto espera a la
  /// siguiente pieza.
  static const int garbagePerLock = 8;

  final int startLevel;
  final math.Random _random;
  final List<TsumikiPiece> _bag = <TsumikiPiece>[];

  /// El tablero, fila a fila desde arriba (incluidas las ocultas).
  final List<TsumikiPiece?> cells = List<TsumikiPiece?>.filled(width * rows, null);

  TsumikiStatus status = TsumikiStatus.ready;
  FallingPiece? current;
  TsumikiPiece? held;
  bool canHold = true;

  int score = 0;
  int lines = 0;
  int tsumikis = 0;
  int maxCombo = 0;
  int _combo = 0;
  bool _lastWasTsumiki = false;

  double _fall = 0;
  double _lock = 0;
  int _resets = 0;

  /// Filas que se estan borrando y cuanto le queda al destello.
  List<int> clearing = const <int>[];
  double _clearLeft = 0;

  /// Versus: cuanto mas rapido cae (un sabotaje lo sube) y si la reserva
  /// esta bloqueada.
  double speedFactor = 1;
  bool holdLocked = false;

  /// Filas grises por subir, en tandas: cada una con su hueco.
  final List<({int rows, int hole})> _garbage = [];

  int get level => startLevel + lines ~/ 10;

  /// Segundos por fila, la curva de siempre: 1 s en el nivel 1 y cada vez
  /// menos, hasta casi caer de golpe hacia el nivel 20.
  double get gravity {
    final l = math.min(level, 20) - 1;
    return math.pow(.8 - l * .007, l).toDouble() / speedFactor;
  }

  /// Filas grises que esperan para subir.
  int get pendingGarbage => _garbage.fold(0, (a, g) => a + g.rows);

  /// Recibe [rows] filas grises con el hueco en la columna [hole]. Suben al
  /// asentarse la siguiente pieza que no borre filas.
  void queueGarbage(int rows, int hole) {
    if (rows <= 0) return;
    _garbage.add((rows: rows, hole: hole.clamp(0, width - 1)));
  }

  /// Borrar filas compensa las grises que esperan: devuelve lo que sobra
  /// para mandarlo al otro.
  int cancelGarbage(int rows) {
    var left = rows;
    while (left > 0 && _garbage.isNotEmpty) {
      final g = _garbage.first;
      if (g.rows <= left) {
        left -= g.rows;
        _garbage.removeAt(0);
      } else {
        _garbage[0] = (rows: g.rows - left, hole: g.hole);
        left = 0;
      }
    }
    return left;
  }

  /// El tablero visible, una letra por casilla y fila a fila desde arriba
  /// ('.' vacia). Para pintar al otro en el versus.
  String encodeBoard() {
    final b = StringBuffer();
    for (var i = hiddenRows * width; i < cells.length; i++) {
      b.write(cells[i]?.code ?? '.');
    }
    return b.toString();
  }

  /// Lo contrario de [encodeBoard]; lo que no encaje se queda vacio.
  static List<TsumikiPiece?> decodeBoard(String code) => [
        for (var i = 0; i < width * visibleRows; i++)
          i < code.length ? TsumikiPiece.fromCode(code[i]) : null,
      ];

  /// Progreso del destello de las filas completas, de 0 a 1.
  double get clearProgress => clearing.isEmpty ? 0 : 1 - _clearLeft / clearDelay;

  /// Las tres siguientes.
  List<TsumikiPiece> get next => _bag.take(3).toList();

  bool get isOver => status == TsumikiStatus.over;

  TsumikiPiece? at(int x, int y) => cells[y * width + x];

  /// Fila visible (0 arriba) de la casilla ocupada mas alta, o
  /// [visibleRows] si el tablero esta vacio.
  int get stackTop {
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < width; x++) {
        if (cells[y * width + x] != null) return y - hiddenRows;
      }
    }
    return visibleRows;
  }

  /// Donde caeria la pieza si se soltase ahora.
  FallingPiece? get ghost {
    var p = current;
    if (p == null) return null;
    while (_fits(p!.moved(0, 1))) {
      p = p.moved(0, 1);
    }
    return p;
  }

  void start() {
    if (status != TsumikiStatus.ready) return;
    status = TsumikiStatus.playing;
    _spawn(_take());
  }

  void pause() {
    if (status == TsumikiStatus.playing) status = TsumikiStatus.paused;
  }

  void resume() {
    if (status == TsumikiStatus.paused) status = TsumikiStatus.playing;
  }

  bool get _live => status == TsumikiStatus.playing && current != null && clearing.isEmpty;

  bool move(int dx) {
    if (!_live) return false;
    final p = current!.moved(dx, 0);
    if (!_fits(p)) return false;
    current = p;
    _touched();
    return true;
  }

  /// Gira a la derecha ([clockwise]) o a la izquierda, con empujes.
  bool rotate({bool clockwise = true}) {
    if (!_live) return false;
    final p = current!;
    if (p.type == TsumikiPiece.o) return false;
    final from = p.rotation;
    final to = (from + (clockwise ? 1 : 3)) % 4;
    final kicks = (p.type == TsumikiPiece.i ? _kicksI : _kicksJlstz)[from * 10 + to]!;
    for (final (kx, ky) in kicks) {
      final q = p.moved(kx, -ky, to);
      if (_fits(q)) {
        current = q;
        _touched();
        return true;
      }
    }
    return false;
  }

  /// Baja una fila a mano: un punto por fila.
  bool softDrop() {
    if (!_live) return false;
    final p = current!.moved(0, 1);
    if (!_fits(p)) return false;
    current = p;
    _fall = 0;
    score += 1;
    return true;
  }

  /// Suelta la pieza de golpe: dos puntos por fila. Devuelve la distancia y
  /// lo que ha pasado al asentarse.
  (int, LockEvent)? hardDrop() {
    if (!_live) return null;
    final from = current!.y;
    final to = ghost!;
    current = to;
    final d = to.y - from;
    score += d * 2;
    return (d, _lockPiece());
  }

  /// Guarda la pieza (una vez por pieza) y saca la guardada o la siguiente.
  bool hold() {
    if (!_live || !canHold || holdLocked) return false;
    final type = current!.type;
    final out = held;
    held = type;
    canHold = false;
    _spawn(out ?? _take());
    return true;
  }

  /// Avanza el tiempo. Devuelve el asentamiento si la gravedad lo provoca.
  LockEvent? tick(double dt) {
    if (status != TsumikiStatus.playing) return null;
    if (clearing.isNotEmpty) {
      _clearLeft -= dt;
      if (_clearLeft <= 0) _finishClear();
      return null;
    }
    final p = current;
    if (p == null) return null;
    if (_fits(p.moved(0, 1))) {
      _lock = 0;
      _fall += dt;
      while (_fall >= gravity) {
        _fall -= gravity;
        final q = current!.moved(0, 1);
        if (!_fits(q)) break;
        current = q;
      }
      return null;
    }
    _lock += dt;
    if (_lock >= lockDelay) return _lockPiece();
    return null;
  }

  // --- Por dentro ---------------------------------------------------------

  void _refill() {
    final bag = List<TsumikiPiece>.of(TsumikiPiece.playable)..shuffle(_random);
    _bag.addAll(bag);
  }

  TsumikiPiece _take() {
    final t = _bag.removeAt(0);
    if (_bag.length < 7) _refill();
    return t;
  }

  bool _fits(FallingPiece p) {
    for (final (x, y) in p.cells) {
      if (x < 0 || x >= width || y < 0 || y >= rows) return false;
      if (cells[y * width + x] != null) return false;
    }
    return true;
  }

  void _touched() {
    // Moverse en el suelo estira el tiempo para asentarse, con limite.
    if (current != null && !_fits(current!.moved(0, 1)) && _resets < lockResets) {
      _lock = 0;
      _resets++;
    }
  }

  void _spawn(TsumikiPiece type) {
    final x = type == TsumikiPiece.o ? 4 : 3;
    final p = FallingPiece(type, 0, x, 0);
    _fall = 0;
    _lock = 0;
    _resets = 0;
    if (!_fits(p)) {
      current = null;
      status = TsumikiStatus.over;
      return;
    }
    // Nace en las filas ocultas y asoma enseguida, si hay sitio.
    current = _fits(p.moved(0, 1)) ? p.moved(0, 1) : p;
  }

  LockEvent _lockPiece() {
    final p = current!;
    final placed = <int>[];
    var hidden = true;
    for (final (x, y) in p.cells) {
      cells[y * width + x] = p.type;
      placed.add(y * width + x);
      if (y >= hiddenRows) hidden = false;
    }
    current = null;
    canHold = true;

    final full = <int>[
      for (var y = 0; y < rows; y++)
        if (List<int>.generate(width, (x) => x).every((x) => cells[y * width + x] != null)) y,
    ];
    final levelBefore = level;
    var points = 0;
    var b2b = false;
    if (full.isNotEmpty) {
      _combo++;
      maxCombo = math.max(maxCombo, _combo);
      final tsumiki = full.length == 4;
      b2b = tsumiki && _lastWasTsumiki;
      points = linePoints[full.length] * levelBefore;
      if (b2b) points = points * 3 ~/ 2;
      if (_combo > 1) points += 50 * (_combo - 1) * levelBefore;
      if (tsumiki) tsumikis++;
      _lastWasTsumiki = tsumiki;
      score += points;
      lines += full.length;
      clearing = full;
      _clearLeft = clearDelay;
    } else {
      _combo = 0;
    }

    // Se asienta entera por encima del tablero: fin.
    final over = full.isEmpty && hidden;
    var garbageIn = 0;
    if (over) {
      status = TsumikiStatus.over;
    } else if (full.isEmpty) {
      garbageIn = _riseGarbage();
      if (status != TsumikiStatus.over) _spawn(_take());
    }
    return LockEvent(
      cells: placed,
      rows: full,
      points: points,
      combo: full.isEmpty ? 0 : _combo,
      backToBack: b2b,
      levelUp: level > levelBefore,
      gameOver: status == TsumikiStatus.over,
      garbageIn: garbageIn,
    );
  }

  /// Sube las filas grises que esperan, hasta [garbagePerLock]. Si algo se
  /// sale por arriba, se acaba.
  int _riseGarbage() {
    var n = 0;
    while (_garbage.isNotEmpty && n < garbagePerLock) {
      final g = _garbage.first;
      final take = math.min(g.rows, garbagePerLock - n);
      for (var k = 0; k < take; k++) {
        for (var x = 0; x < width; x++) {
          if (cells[x] != null) status = TsumikiStatus.over;
        }
        cells.setRange(0, cells.length - width, cells, width);
        for (var x = 0; x < width; x++) {
          cells[cells.length - width + x] = x == g.hole ? null : TsumikiPiece.garbage;
        }
      }
      n += take;
      if (take == g.rows) {
        _garbage.removeAt(0);
      } else {
        _garbage[0] = (rows: g.rows - take, hole: g.hole);
      }
    }
    return n;
  }

  void _finishClear() {
    final gone = clearing.toSet();
    final kept = <List<TsumikiPiece?>>[
      for (var y = 0; y < rows; y++)
        if (!gone.contains(y)) cells.sublist(y * width, (y + 1) * width),
    ];
    final empty = List<List<TsumikiPiece?>>.generate(gone.length, (_) => List<TsumikiPiece?>.filled(width, null));
    final all = [...empty, ...kept];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < width; x++) {
        cells[y * width + x] = all[y][x];
      }
    }
    clearing = const <int>[];
    _spawn(_take());
  }
}

/// Monedas al acabar, segun las filas. Las reglas solo aceptan 3, 5 u 8.
int tsumikiRewardFor(int lines) => lines >= 50
    ? 8
    : lines >= 25
        ? 5
        : lines >= 10
            ? 3
            : 0;
