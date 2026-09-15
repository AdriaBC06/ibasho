// Ibasho — bloqueo de versiones antiguas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/live_tree.dart';
import '../core/version.dart';
import 'providers.dart';

/// `/system/update`: la version minima que se deja usar y donde descargar la
/// nueva.
@immutable
class UpdateRequirement {
  const UpdateRequirement({required this.minVersion, this.url});

  final AppVersion minVersion;

  /// Pagina de descarga (`https://…`), si la hay.
  final String? url;

  /// Si esta build se tiene que actualizar para seguir.
  bool blocks(AppVersion version) => version < minVersion;

  static UpdateRequirement? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final min = raw['minVersion'];
    final parsed = min is String ? AppVersion.tryParse(min) : null;
    if (parsed == null) return null;
    final url = raw['url'];
    return UpdateRequirement(minVersion: parsed, url: url is String && url.isNotEmpty ? url : null);
  }
}

/// La version minima exigida, en tiempo real.
///
/// Se lee sin sesion (las reglas lo dejan publico), asi que bloquea tambien la
/// pantalla de login, y al subir el admin la version minima una app ya abierta
/// se cierra en el acto. Si no hay red o el nodo no existe, no bloquea: sin
/// servidor la app tampoco hace nada, y dejar a alguien encerrado por un fallo
/// de red seria peor.
///
/// Es un cerrojo de la app, no de las reglas: un cliente modificado podria
/// saltarselo. Sirve para que el grupo actualice, no como seguridad.
final updateRequirementProvider = StreamProvider<UpdateRequirement?>((ref) async* {
  final backend = ref.watch(backendProvider);
  const path = '/system/update';
  Object? tree;
  try {
    tree = await backend.read(path, idToken: '');
    yield UpdateRequirement.fromJson(tree);
  } catch (e) {
    debugPrint('Ibasho: no se ha podido leer la version minima ($e)');
    yield null;
  }
  await for (final event in backend.watch(path, token: () async => '')) {
    tree = applyDatabaseEvent(tree, event);
    yield UpdateRequirement.fromJson(tree);
  }
});

/// Si esta build esta bloqueada ahora mismo.
final updateLockedProvider = Provider<bool>((ref) {
  final requirement = ref.watch(updateRequirementProvider).valueOrNull;
  return requirement?.blocks(AppVersion.current) ?? false;
});
