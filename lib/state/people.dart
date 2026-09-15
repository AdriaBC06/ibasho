// Ibasho — lo que se ve de otras personas, en tiempo real.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/social.dart';
import '../backend/tama.dart';
import 'providers.dart';

/// Un nodo de la base, leido y luego seguido en tiempo real.
///
/// La primera lectura va por REST para que un "sin permiso" (alguien que ha
/// dejado de ser amigo) llegue como error en vez de quedarse reintentando.
Stream<Object?> _liveNode(Ref ref, String path) {
  final backend = ref.watch(backendProvider);
  final session = ref.watch(sessionProvider.notifier);
  ref.watch(sessionProvider.select((s) => s.accountId));
  return () async* {
    Object? tree = await backend.read(path, idToken: await session.freshToken());
    var last = jsonEncode(tree);
    yield tree;
    await for (final event in backend.watch(path, token: session.freshToken)) {
      tree = applyDatabaseEvent(tree, event);
      final encoded = jsonEncode(tree);
      if (encoded == last) continue;
      last = encoded;
      yield tree;
    }
  }();
}

/// Mantiene vivo un proveedor un par de minutos despues de dejar de mirarlo:
/// pasar de pagina y volver no vuelve a pedir nada.
void _linger(Ref ref) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() => timer = Timer(const Duration(minutes: 2), link.close));
  ref.onResume(() => timer?.cancel());
  ref.onDispose(() => timer?.cancel());
}

/// La ficha de cualquier cuenta. `null` si aun no la ha estrenado.
final cardOfProvider = StreamProvider.autoDispose.family<UserCard?, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/card').map(UserCard.fromJson);
});

/// El Tama de perfil de una cuenta, tal como lo dejan leer las reglas: nombre,
/// personalidad, voz y aspecto. Los cuidados no se ven.
final publicTamaProvider =
    StreamProvider.autoDispose.family<Tama?, (String owner, String tamaId)>((ref, key) {
  _linger(ref);
  final (owner, id) = key;
  const parts = ['name', 'personality', 'voice', 'look'];
  final values = <String, Object?>{};
  final controller = StreamController<Tama?>();
  final subscriptions = <StreamSubscription<Object?>>[];

  void emit() {
    if (!parts.every(values.containsKey)) return;
    if (values['name'] is! String) {
      controller.add(null);
      return;
    }
    controller.add(Tama.fromJson(id, {
      'creator': owner,
      'keeper': owner,
      for (final part in parts) part: values[part],
    }));
  }

  for (final part in parts) {
    subscriptions.add(_liveNode(ref, '/tamas/$id/$part').listen(
      (value) {
        values[part] = value;
        emit();
      },
      onError: (Object e) {
        debugPrint('Ibasho: Tama publico $id/$part ($e)');
        if (!controller.isClosed) controller.add(null);
      },
    ));
  }
  ref.onDispose(() {
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(controller.close());
  });
  return controller.stream;
});

/// El perfil completo de un amigo.
final friendProfileProvider =
    StreamProvider.autoDispose.family<UserProfile?, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/profile')
      .map((raw) => raw is Map ? UserProfile.fromJson(raw) : null);
});

/// La presencia de un amigo.
final presenceOfProvider = StreamProvider.autoDispose.family<Presence, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/presence').map(Presence.fromJson);
});

/// Musica de un amigo: la pista de su perfil y las que tiene desbloqueadas.
@immutable
class MusicOf {
  const MusicOf({this.profileTrack, this.unlocked = const <String>{}});

  final String? profileTrack;
  final Set<String> unlocked;
}

final musicOfProvider = StreamProvider.autoDispose.family<MusicOf, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/music').map((raw) {
    if (raw is! Map) return const MusicOf();
    final unlocked = raw['unlocked'];
    return MusicOf(
      profileTrack: raw['profileTrack'] as String?,
      unlocked: unlocked is Map
          ? {
              for (final e in unlocked.entries)
                if (e.value == true) '${e.key}',
            }
          : const <String>{},
    );
  });
});

/// El muro de cumpleaños de una cuenta (la propia o la de un amigo).
final wallOfProvider =
    StreamProvider.autoDispose.family<Map<int, List<WallMessage>>, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/wall').map(parseWall);
});

/// Cuantos amigos tiene un amigo.
final friendCountOfProvider = StreamProvider.autoDispose.family<int, String>((ref, account) {
  _linger(ref);
  return _liveNode(ref, '/users/$account/friendCount').map((raw) => raw is num ? raw.toInt() : 0);
});
