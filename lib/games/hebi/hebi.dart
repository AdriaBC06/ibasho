// Ibasho — Hebi: la serpiente clasica, sin pantalla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:collection';
import 'dart:math' as math;

import '../../backend/tama.dart';

enum HebiStatus { ready, playing, paused, over }

enum HebiDir {
  up(0, -1),
  down(0, 1),
  left(-1, 0),
  right(1, 0);

  const HebiDir(this.dx, this.dy);

  final int dx;
  final int dy;

  HebiDir get opposite => switch (this) {
        HebiDir.up => HebiDir.down,
        HebiDir.down => HebiDir.up,
        HebiDir.left => HebiDir.right,
        HebiDir.right => HebiDir.left,
      };
}

/// Una casilla del tablero.
typedef Cell = (int, int);

/// Lo que ha pasado en un paso: si ha comido, si sube de velocidad y si se
/// ha acabado (y por que).
class HebiStep {
  const HebiStep({this.ate, this.speedUp = false, this.over = false, this.won = false});

  /// La comida que se ha comido en este paso, si alguna.
  final TamaFood? ate;
  final bool speedUp;
  final bool over;

  /// Ha llenado el tablero entero.
  final bool won;
}

/// La partida.
///
/// Un tablero de [width]x[height] con paredes: chocar con ellas o con la
/// propia cola acaba la partida. La serpiente empieza con [startLength]
/// casillas y crece una por cada comida; cada [foodsPerSpeed] comidas va mas
/// rapida. La puntuacion es la longitud.
///
/// El tiempo lo lleva [tick]: avanza una casilla cada [interval] segundos.
/// Los giros se encolan (hasta dos) para que un doble giro rapido, como
/// arriba-izquierda para dar media vuelta, no se pierda entre dos pasos.
class HebiGame {
  HebiGame({int? seed}) : _random = math.Random(seed) {
    final y = height ~/ 2;
    for (var i = 0; i < startLength; i++) {
      _body.add((width ~/ 2 - 2 - i, y));
    }
    _occupied.addAll(_body);
    _prev = List<Cell>.of(_body);
    _placeFood();
  }

  static const int width = 15;
  static const int height = 15;
  static const int startLength = 3;
  static const int foodsPerSpeed = 5;
  static const int maxSpeed = 12;

  final math.Random _random;

  /// De la cabeza a la cola.
  final ListQueue<Cell> _body = ListQueue<Cell>();
  final Set<Cell> _occupied = <Cell>{};
  List<Cell> _prev = const <Cell>[];

  HebiStatus status = HebiStatus.ready;
  HebiDir _dir = HebiDir.right;
  final List<HebiDir> _queue = <HebiDir>[];

  Cell? food;
  TamaFood foodKind = TamaFood.cookie;

  int eaten = 0;
  double _acc = 0;
  double _time = 0;

  /// Acelerar mientras se mantiene pulsado (el boton A o espacio).
  bool boost = false;

  Iterable<Cell> get body => _body;
  Cell get head => _body.first;
  int get length => _body.length;
  HebiDir get dir => _dir;
  bool get isOver => status == HebiStatus.over;

  /// Segundos jugados (sin las pausas).
  double get time => _time;

  /// Donde estaba cada trozo antes del ultimo paso, para pintar el
  /// movimiento suave entre casillas. Puede tener uno menos que [body]
  /// (justo despues de comer).
  List<Cell> get previous => _prev;

  /// De 1 a [maxSpeed].
  int get speed => math.min(maxSpeed, 1 + eaten ~/ foodsPerSpeed);

  /// Segundos por casilla: 0,18 al principio y un 8 % menos por nivel.
  double get interval {
    final base = .18 * math.pow(.92, speed - 1);
    return boost ? base * .5 : base;
  }

  /// Lo que lleva del paso en curso, de 0 a 1.
  double get progress => (_acc / interval).clamp(0.0, 1.0);

  /// La casilla de delante de la cabeza con la direccion actual.
  Cell get ahead => (head.$1 + _nextDir.dx, head.$2 + _nextDir.dy);

  HebiDir get _nextDir => _queue.isEmpty ? _dir : _queue.first;

  /// Si la casilla de delante es pared o cola: el Tama se agobia.
  bool get danger => status == HebiStatus.playing && _blocked(ahead, growing: false);

  bool _inside(Cell c) => c.$1 >= 0 && c.$1 < width && c.$2 >= 0 && c.$2 < height;

  /// La cola se mueve en el mismo paso, asi que su casilla no cuenta, salvo
  /// si la serpiente va a crecer.
  bool _blocked(Cell c, {required bool growing}) {
    if (!_inside(c)) return true;
    if (!_occupied.contains(c)) return false;
    return growing || c != _body.last;
  }

  void start() {
    if (status != HebiStatus.ready) return;
    status = HebiStatus.playing;
  }

  void pause() {
    if (status == HebiStatus.playing) status = HebiStatus.paused;
  }

  void resume() {
    if (status == HebiStatus.paused) status = HebiStatus.playing;
  }

  /// Gira hacia [d]. No se puede dar media vuelta sobre uno mismo ni repetir
  /// la direccion que ya lleva. Devuelve si se ha encolado.
  bool turn(HebiDir d) {
    if (status != HebiStatus.playing && status != HebiStatus.ready) return false;
    final last = _queue.isEmpty ? _dir : _queue.last;
    if (d == last || d == last.opposite || _queue.length >= 2) return false;
    _queue.add(d);
    return true;
  }

  /// Avanza el reloj [dt] segundos. Devuelve el ultimo paso que haya dado,
  /// si ha dado alguno.
  HebiStep? tick(double dt) {
    if (status != HebiStatus.playing) return null;
    _time += dt;
    _acc += dt;
    HebiStep? last;
    // Un salto grande no puede dar mas de dos pasos de golpe.
    var steps = 0;
    while (_acc >= interval && status == HebiStatus.playing && steps < 2) {
      _acc -= interval;
      steps++;
      final step = this.step();
      if (last == null || step.ate != null || step.over || step.speedUp) last = step;
    }
    if (steps == 2) _acc = math.min(_acc, interval * .5);
    return last;
  }

  /// Un paso de una casilla. Publico para los tests.
  HebiStep step() {
    if (_queue.isNotEmpty) _dir = _queue.removeAt(0);
    final next = (head.$1 + _dir.dx, head.$2 + _dir.dy);
    final growing = next == food;
    if (_blocked(next, growing: growing)) {
      status = HebiStatus.over;
      _prev = List<Cell>.of(_body);
      return const HebiStep(over: true);
    }
    _prev = List<Cell>.of(_body);
    _body.addFirst(next);
    if (!growing) {
      _occupied.remove(_body.removeLast());
    }
    _occupied.add(next);
    if (!growing) return const HebiStep();

    final ate = foodKind;
    final before = speed;
    eaten++;
    if (_occupied.length == width * height) {
      food = null;
      status = HebiStatus.over;
      return HebiStep(ate: ate, over: true, won: true);
    }
    _placeFood();
    return HebiStep(ate: ate, speedUp: speed > before);
  }

  void _placeFood() {
    final free = <Cell>[
      for (var y = 0; y < height; y++)
        for (var x = 0; x < width; x++)
          if (!_occupied.contains((x, y))) (x, y),
    ];
    if (free.isEmpty) {
      food = null;
      return;
    }
    food = free[_random.nextInt(free.length)];
    foodKind = TamaFood.values[_random.nextInt(TamaFood.values.length)];
  }
}

/// Monedas por partida segun la longitud final: 15 o mas dan 3, 30 dan 5 y
/// 50 dan 8. Dentro del tope diario de cada juego, como el resto.
int hebiRewardFor(int length) => length >= 50
    ? 8
    : length >= 30
        ? 5
        : length >= 15
            ? 3
            : 0;
