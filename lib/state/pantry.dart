// Ibasho — la despensa: las chuches que tiene guardadas la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/shop.dart';
import '../backend/tama.dart';
import 'session.dart';

/// Chuches que se pueden comprar en el Yatai y ver en la despensa.
///
/// Desde la 0.6.0 son todas: las que no son de serie (galleta y caramelo)
/// empiezan a 0 unidades y hay que comprarlas, pero ya no llevan candado.
final unlockedFoodsProvider = Provider<Set<TamaFood>>(
  (ref) => TamaFood.values.toSet(),
);

/// La despensa de la cuenta: unidades de cada comida.
///
/// Sigue `/users/{cuenta}/pantry` en tiempo real. La primera vez que falta el
/// nodo de una comida de serie, pide el stock inicial de 5 unidades; las
/// reglas solo lo dejan pasar la primera vez, asi que un segundo intento (por
/// ejemplo, si dos equipos arrancan a la vez) simplemente se descarta.
class PantryController extends StateNotifier<Map<TamaFood, int>> {
  PantryController({
    required IbashoBackend backend,
    required SessionController session,
  }) : _backend = backend,
       _session = session,
       super(const <TamaFood, int>{}) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;

  /// Las de serie: las unicas que reciben el stock inicial gratis. Las demas
  /// empiezan a 0 y hay que comprarlas en el Yatai.
  static final Set<TamaFood> _starterFoods = {
    for (final food in TamaFood.values)
      if (food.unlockedByDefault) food,
  };

  StreamSubscription<DatabaseEvent>? _watch;

  /// Copia del nodo `/pantry`: el stream trae cambios sueltos (`/cookie`)
  /// ademas del nodo entero.
  Object? _tree;

  /// Comidas para las que ya se ha pedido el stock inicial en esta sesion, se
  /// haya aceptado o no: no tiene sentido volver a intentarlo cada vez que
  /// llega un evento del stream.
  final Set<TamaFood> _starterRequested = <TamaFood>{};

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final raw = await _backend.read('/users/$_me/pantry', idToken: token);
      _tree = raw;
      if (mounted) state = _parse(raw);
      unawaited(_ensureStarters());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer la despensa ($e)');
    }
    if (!mounted) return;
    _watch = _backend
        .watch('/users/$_me/pantry', token: _session.freshToken)
        .listen(
          (event) {
            _tree = applyDatabaseEvent(_tree, event);
            if (!mounted) return;
            state = _parse(_tree);
            unawaited(_ensureStarters());
          },
          onError: (Object e) =>
              debugPrint('Ibasho: stream de la despensa ($e)'),
        );
  }

  static Map<TamaFood, int> _parse(Object? raw) {
    if (raw is! Map) return const <TamaFood, int>{};
    final out = <TamaFood, int>{};
    for (final entry in raw.entries) {
      final qty = entry.value;
      if (qty is! num) continue;
      for (final food in TamaFood.values) {
        // Un -1 (u otro negativo) de una cuenta que quedo mal no se ensena
        // ni se usa: se trata como si no quedara nada.
        if (food.name == entry.key) out[food] = qty.toInt() < 0 ? 0 : qty.toInt();
      }
    }
    return Map<TamaFood, int>.unmodifiable(out);
  }

  /// Pide el stock inicial de las comidas de serie que aun no tengan nodo.
  Future<void> _ensureStarters() async {
    for (final food in _starterFoods) {
      if (state.containsKey(food) || _starterRequested.contains(food)) continue;
      _starterRequested.add(food);
      try {
        final token = await _session.freshToken();
        await _backend.write(
          '/users/$_me/pantry/${food.name}',
          starterFoodUnits,
          idToken: token,
        );
      } catch (e) {
        // Puede que otro equipo ya lo haya pedido a la vez: las reglas
        // rechazan el segundo intento y aqui no pasa nada, el stream trae el
        // valor real en cuanto llegue.
        debugPrint(
          'Ibasho: no se ha podido dar el stock inicial de ${food.name} ($e)',
        );
      }
    }
  }

  /// Come una unidad. `false` si no quedaba ninguna o si el servidor la
  /// rechaza.
  Future<bool> consume(TamaFood food) async {
    final current = state[food] ?? 0;
    if (current <= 0) return false;
    final next = current - 1;
    // Se ve al instante; si la escritura falla, se deshace.
    state = {...state, food: next};
    try {
      await _backend.write(
        '/users/$_me/pantry/${food.name}',
        next,
        idToken: await _session.freshToken(),
      );
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido comer ($e)');
      if (mounted) state = {...state, food: current};
      return false;
    }
  }
}
