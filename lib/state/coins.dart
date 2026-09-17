// Ibasho — las monedas de la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/models.dart';
import 'session.dart';

/// Tope de monedas. El mismo que comprueban las reglas.
const int maxCoins = 999999999;

/// El monedero, que hoy no gasta nadie.
///
/// Las monedas se ven en la barra de estado y estan a cero para todo el mundo:
/// lo que hace falta ya de la 0.4.0 es que **nadie pueda ponerselas a si
/// mismo**. Por eso `/users/{cuenta}/coins` solo lo escribe un admin, y la app
/// no tiene ni una ruta que lo intente desde la cuenta propia.
class CoinsController extends StateNotifier<int> {
  CoinsController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(0) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;

  StreamSubscription<DatabaseEvent>? _watch;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final raw = await _backend.read('/users/$_me/coins', idToken: token);
      if (mounted && raw is num) state = raw.toInt();
    } catch (e) {
      debugPrint('Ibasho: no se han podido leer las monedas ($e)');
    }
    if (!mounted) return;
    _watch = _backend.watch('/users/$_me/coins', token: _session.freshToken).listen((e) {
      if (mounted && e.path == '/') state = e.data is num ? (e.data! as num).toInt() : 0;
    }, onError: (Object e) => debugPrint('Ibasho: stream de monedas ($e)'));
  }

  /// Pone las monedas de una cuenta. Solo sale bien desde un admin: es la
  /// regla la que lo decide, no esta comprobacion.
  Future<bool> setFor(String accountId, int amount) async {
    if (amount < 0 || amount > maxCoins) return false;
    try {
      final token = await _session.freshToken();
      await _backend.write('/users/$accountId/coins', amount, idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se han podido dar las monedas ($e)');
      return false;
    }
  }
}
