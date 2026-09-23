// Ibasho — orden de los canales del HOME, guardado en la cuenta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../ui/screens/channels/channel.dart';
import 'session.dart';

@immutable
class ChannelOrderState {
  const ChannelOrderState({this.order = const <String>[], this.loaded = false});

  /// Ids de canal en el orden elegido por la cuenta. Puede tener ids que ya
  /// no existan (se ignoran al pintar) y le pueden faltar los mas nuevos (van
  /// al final, ver [applyChannelOrder]).
  final List<String> order;

  final bool loaded;

  ChannelOrderState copyWith({List<String>? order, bool? loaded}) =>
      ChannelOrderState(order: order ?? this.order, loaded: loaded ?? this.loaded);
}

/// El orden de los canales de una cuenta, en `/users/{cuenta}/channelOrder`.
///
/// Es solo una lista de ids: nada de posiciones por indice, porque la rejilla
/// cambia de canales entre cuentas y entre versiones (nuevos que llegan,
/// otros que se desbloquean mas tarde). Ver [applyChannelOrder].
class ChannelOrderController extends StateNotifier<ChannelOrderState> {
  ChannelOrderController({required IbashoBackend backend, required SessionController session})
      : _backend = backend,
        _session = session,
        super(const ChannelOrderState()) {
    unawaited(_load());
  }

  final IbashoBackend _backend;
  final SessionController _session;

  String get _path => '/users/${_session.state.accountId}/channelOrder';

  Future<void> _load() async {
    if (_session.state.accountId.isEmpty) return;
    try {
      final raw = await _backend.read(_path, idToken: await _session.freshToken());
      final order = <String>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is String) order.add(item);
        }
      } else if (raw is Map) {
        // Guardado como mapa de indices ("0", "1"...) si algun hueco quedo
        // vacio; se recorre en el orden de las claves numericas.
        final keys = raw.keys.map((k) => '$k').toList()
          ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
        for (final key in keys) {
          final value = raw[key];
          if (value is String) order.add(value);
        }
      }
      if (!mounted) return;
      state = ChannelOrderState(order: order, loaded: true);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el orden de canales ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
  }

  /// Guarda un orden nuevo, ya al completo (no un cambio suelto).
  Future<void> setOrder(List<String> order) async {
    state = state.copyWith(order: order);
    try {
      await _backend.write(_path, order, idToken: await _session.freshToken());
    } catch (e) {
      debugPrint('Ibasho: no se ha podido guardar el orden de canales ($e)');
    }
  }
}

/// Aplica el orden guardado a la lista de canales de hoy.
///
/// Los ids guardados que existen van primero, en ese orden; los canales de
/// hoy que no estaban guardados (nuevos, o desbloqueados despues de guardar)
/// van detras, en su orden de siempre; un id guardado que ya no existe se
/// ignora sin mas.
List<ChannelSpec> applyChannelOrder(List<ChannelSpec> channels, List<String> order) {
  if (order.isEmpty) return channels;
  final byId = {for (final c in channels) c.id: c};
  final used = <String>{};
  final result = <ChannelSpec>[];
  for (final id in order) {
    final spec = byId[id];
    if (spec != null && used.add(id)) result.add(spec);
  }
  for (final spec in channels) {
    if (used.add(spec.id)) result.add(spec);
  }
  return result;
}
