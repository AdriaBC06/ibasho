// Malla — Guardia, minijuego de espera portado a Flutter.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/type.dart';
import '../../ui/widgets/controls.dart';
import '../../ui/widgets/glyphs.dart';

enum GuardDirection { up, right, down, left }

enum _GuardStage { inbound, turn, attack }

class _GuardProjectile {
  _GuardProjectile({
    required this.source,
    required this.attack,
    required this.yellow,
    required this.speed,
  });

  final GuardDirection source;
  final GuardDirection attack;
  final bool yellow;
  final double speed;
  _GuardStage stage = _GuardStage.inbound;
  double p = 0;
  double turnT = 0;
}

class MallaGuard extends StatefulWidget {
  const MallaGuard({
    super.key,
    required this.marker,
    required this.color,
    required this.best,
    required this.soundEnabled,
    required this.onBestChanged,
  });

  final String marker;
  final Color color;
  final int best;
  final bool soundEnabled;
  final ValueChanged<int> onBestChanged;

  @override
  State<MallaGuard> createState() => _MallaGuardState();
}

class _MallaGuardState extends State<MallaGuard>
    with SingleTickerProviderStateMixin {
  final math.Random _random = math.Random();
  final FocusNode _focus = FocusNode();
  final List<_GuardProjectile> _projectiles = <_GuardProjectile>[];
  late final Ticker _ticker;

  GuardDirection _direction = GuardDirection.up;
  int _score = 0;
  int _lives = 3;
  late int _best;
  bool _paused = false;
  bool _gameOver = false;
  Duration? _last;
  double _untilSpawn = .65;

  @override
  void initState() {
    super.initState();
    _best = widget.best;
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(MallaGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.best > _best) _best = widget.best;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final before = _last;
    _last = elapsed;
    if (before == null || _paused || _gameOver || !mounted) return;
    final dt = ((elapsed - before).inMicroseconds / 1000000)
        .clamp(0.0, .05)
        .toDouble();
    _untilSpawn -= dt;
    if (_untilSpawn <= 0) {
      final spawned = _spawn();
      final interval = math.max(.43, 1.12 - _score * .018);
      _untilSpawn = spawned
          ? interval * (.84 + _random.nextDouble() * .32)
          : .12;
    }

    final remove = <_GuardProjectile>[];
    for (final projectile in _projectiles) {
      _advance(projectile, dt);
      final contact = _contact(projectile);
      if (contact != 0) {
        remove.add(projectile);
        _resolve(contact > 0);
      }
    }
    _projectiles.removeWhere(remove.contains);
    if (mounted) setState(() {});
  }

  bool _spawn() {
    if (_projectiles.any((p) => p.yellow)) return false;
    final wantYellow =
        _projectiles.isEmpty &&
        _score >= 2 &&
        _random.nextDouble() < math.min(.34, .20 + _score * .008);
    final dirs = GuardDirection.values;
    List<GuardDirection> free;
    if (wantYellow) {
      free = List<GuardDirection>.from(dirs);
    } else {
      free = <GuardDirection>[
        for (final dir in dirs)
          if (!_projectiles.any((p) => p.yellow || p.source == dir)) dir,
      ];
    }
    if (free.isEmpty) return false;
    final source = free[_random.nextInt(free.length)];
    final attack = wantYellow ? _opposite(source) : source;
    final speed = math.min(
      .72,
      .38 + _score * .009 + _random.nextDouble() * .08,
    );
    _projectiles.add(
      _GuardProjectile(
        source: source,
        attack: attack,
        yellow: wantYellow,
        speed: speed,
      ),
    );
    return true;
  }

  void _advance(_GuardProjectile p, double dt) {
    if (p.yellow && p.stage == _GuardStage.turn) {
      p.turnT += dt * (2.35 + p.speed * .6);
      if (p.turnT >= 1) {
        p.turnT = 1;
        p.stage = _GuardStage.attack;
        p.p = .38;
        _sound(Sfx.tick);
      }
      return;
    }
    p.p += p.speed * dt;
    if (p.yellow && p.stage == _GuardStage.inbound && p.p >= .62) {
      p.stage = _GuardStage.turn;
      p.turnT = 0;
      p.p = .62;
    }
  }

  /// 1 bloqueado, -1 golpe, 0 todavía no toca.
  int _contact(_GuardProjectile p) {
    if (p.yellow && p.stage != _GuardStage.attack) return 0;
    final progress = p.p.clamp(0.0, 1.0).toDouble();
    if (progress < .80) return 0;
    final defend = p.yellow ? p.attack : p.source;
    if (_direction == defend && progress >= .80) return 1;
    if (progress >= .94) return -1;
    return 0;
  }

  void _resolve(bool blocked) {
    if (blocked) {
      _score++;
      HapticFeedback.selectionClick();
      _sound(Sfx.tick);
      if (_score > _best) {
        _best = _score;
        widget.onBestChanged(_best);
      }
    } else {
      _lives--;
      HapticFeedback.mediumImpact();
      _sound(Sfx.error);
      if (_lives <= 0) {
        _lives = 0;
        _gameOver = true;
        _paused = true;
      }
    }
  }

  void _setDirection(GuardDirection direction) {
    if (_paused || _gameOver) return;
    _focus.requestFocus();
    setState(() => _direction = direction);
  }

  void _togglePause() {
    _focus.requestFocus();
    if (_gameOver) {
      _restart();
      return;
    }
    setState(() {
      _paused = !_paused;
      _last = null;
      if (!_paused) _untilSpawn = math.max(_untilSpawn, .18);
    });
  }

  void _restart() {
    setState(() {
      _projectiles.clear();
      _score = 0;
      _lives = 3;
      _direction = GuardDirection.up;
      _paused = false;
      _gameOver = false;
      _last = null;
      _untilSpawn = .62;
    });
    _focus.requestFocus();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent)
      return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp ||
      LogicalKeyboardKey.keyW => GuardDirection.up,
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.keyD => GuardDirection.right,
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.keyS => GuardDirection.down,
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.keyA => GuardDirection.left,
      _ => null,
    };
    if (direction != null) {
      _setDirection(direction);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _sound(Sfx effect) {
    if (widget.soundEnabled) AudioService.instance.play(effect);
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mientras esperas', style: Ty.micro),
                    Text('Guardia', style: Ty.lead),
                  ],
                ),
              ),
              Text('Bloqueos $_score · Récord $_best', style: Ty.caption),
              IbashoButton(
                label: _gameOver
                    ? 'Reintentar'
                    : (_paused ? 'Continuar' : 'Pausa'),
                glyph: _gameOver ? null : Glyph.pause,
                height: 40,
                onPressed: _togglePause,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Protege el centro. Las lanzas amarillas engañan: rodean el centro sin girar y atacan desde el lado opuesto.',
            style: Ty.caption,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              final side = math.min(box.maxWidth, 330.0);
              return Center(
                child: SizedBox(
                  width: side,
                  height: side,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      final c = Offset(side / 2, side / 2);
                      final d = details.localPosition - c;
                      _setDirection(
                        d.dx.abs() > d.dy.abs()
                            ? (d.dx > 0
                                  ? GuardDirection.right
                                  : GuardDirection.left)
                            : (d.dy > 0
                                  ? GuardDirection.down
                                  : GuardDirection.up),
                      );
                    },
                    child: CustomPaint(
                      painter: _GuardPainter(
                        projectiles: _projectiles,
                        direction: _direction,
                        marker: widget.marker,
                        accent: widget.color,
                        ink: skin.ink,
                        hairline: skin.hairline,
                        paused: _paused,
                        gameOver: _gameOver,
                        score: _score,
                        lives: _lives,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _GuardKey(
                '←',
                _direction == GuardDirection.left,
                () => _setDirection(GuardDirection.left),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  _GuardKey(
                    '↑',
                    _direction == GuardDirection.up,
                    () => _setDirection(GuardDirection.up),
                  ),
                  const SizedBox(height: 6),
                  _GuardKey(
                    '↓',
                    _direction == GuardDirection.down,
                    () => _setDirection(GuardDirection.down),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              _GuardKey(
                '→',
                _direction == GuardDirection.right,
                () => _setDirection(GuardDirection.right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Resistencia ${List<String>.filled(_lives, '♥').join(' ')}${List<String>.filled(3 - _lives, '♡').join(' ')} · ↑ ↓ ← → · WASD · P pausa',
            textAlign: TextAlign.center,
            style: Ty.micro,
          ),
        ],
      ),
    );
  }
}

class _GuardKey extends StatelessWidget {
  const _GuardKey(this.label, this.active, this.onPressed);

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IbashoButton(
    label: label,
    tone: active ? ButtonTone.accent : ButtonTone.plain,
    height: 42,
    minWidth: 48,
    onPressed: onPressed,
  );
}

class _GuardPainter extends CustomPainter {
  _GuardPainter({
    required this.projectiles,
    required this.direction,
    required this.marker,
    required this.accent,
    required this.ink,
    required this.hairline,
    required this.paused,
    required this.gameOver,
    required this.score,
    required this.lives,
  });

  final List<_GuardProjectile> projectiles;
  final GuardDirection direction;
  final String marker;
  final Color accent;
  final Color ink;
  final Color hairline;
  final bool paused;
  final bool gameOver;
  final int score;
  final int lives;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = size.center(Offset.zero);
    final radius = s * .43;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = hairline,
    );
    canvas.drawCircle(
      center,
      s * .065,
      Paint()..color = accent.withValues(alpha: .18),
    );
    canvas.drawCircle(
      center,
      s * .065,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );
    _marker(canvas, center, s * .075);

    final shieldCenter = center + _vector(direction) * s * .16;
    final tangent = Offset(-_vector(direction).dy, _vector(direction).dx);
    canvas.drawLine(
      shieldCenter - tangent * s * .055,
      shieldCenter + tangent * s * .055,
      Paint()
        ..color = accent
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );

    for (final p in projectiles) {
      _projectile(canvas, center, radius, s, p);
    }

    if (paused || gameOver) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: s * .62, height: s * .26),
        const Radius.circular(18),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xDD171A1C));
      final title = gameOver ? 'Fin de Guardia' : 'Pausa';
      final subtitle = gameOver
          ? '$score bloqueos'
          : 'La defensa está detenida';
      _text(
        canvas,
        title,
        center.translate(0, -s * .035),
        s * .052,
        const Color(0xFFF6F3EB),
        FontWeight.w700,
      );
      _text(
        canvas,
        subtitle,
        center.translate(0, s * .035),
        s * .035,
        const Color(0xFFD7D2C9),
        FontWeight.w400,
      );
    }
  }

  void _projectile(
    Canvas canvas,
    Offset center,
    double radius,
    double s,
    _GuardProjectile p,
  ) {
    Offset dir;
    double distance;
    if (p.yellow && p.stage == _GuardStage.turn) {
      final ease =
          .5 - .5 * math.cos(math.pi * p.turnT.clamp(0.0, 1.0).toDouble());
      final angle = _angle(p.source) + math.pi * ease;
      dir = Offset(math.cos(angle), math.sin(angle));
      distance = s * .27;
    } else {
      final d = p.yellow && p.stage == _GuardStage.attack ? p.attack : p.source;
      dir = _vector(d);
      distance = radius * (1 - p.p.clamp(0.0, 1.0).toDouble());
    }
    final pos = center + dir * distance;
    final attack = _vector(p.yellow ? p.attack : p.source);
    final tip = pos - attack * s * .075;
    final tail = pos + attack * s * .075;
    final color = p.yellow ? const Color(0xFFE8BD52) : ink;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(tail, tip, paint);
    final normal = Offset(-attack.dy, attack.dx);
    canvas.drawLine(tip, tip + attack * s * .032 + normal * s * .025, paint);
    canvas.drawLine(tip, tip + attack * s * .032 - normal * s * .025, paint);
  }

  void _marker(Canvas canvas, Offset center, double fontSize) => _text(
    canvas,
    marker.isEmpty ? '⬡' : marker,
    center,
    fontSize,
    ink,
    FontWeight.w700,
  );

  static void _text(
    Canvas canvas,
    String value,
    Offset center,
    double size,
    Color color,
    FontWeight weight,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  static Offset _vector(GuardDirection d) => switch (d) {
    GuardDirection.up => const Offset(0, -1),
    GuardDirection.right => const Offset(1, 0),
    GuardDirection.down => const Offset(0, 1),
    GuardDirection.left => const Offset(-1, 0),
  };

  static double _angle(GuardDirection d) => switch (d) {
    GuardDirection.right => 0,
    GuardDirection.down => math.pi / 2,
    GuardDirection.left => math.pi,
    GuardDirection.up => -math.pi / 2,
  };

  @override
  bool shouldRepaint(_GuardPainter old) => true;
}

GuardDirection _opposite(GuardDirection d) => switch (d) {
  GuardDirection.up => GuardDirection.down,
  GuardDirection.down => GuardDirection.up,
  GuardDirection.left => GuardDirection.right,
  GuardDirection.right => GuardDirection.left,
};
