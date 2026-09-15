// Ibasho — la ficha publica de la cuenta, siempre al dia con el perfil.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/models.dart';
import '../backend/social.dart';
import '../backend/tama.dart';
import 'accent_sync.dart';
import 'people.dart';
import 'providers.dart';

/// La ficha que corresponde a un perfil y a un Tama de perfil.
///
/// El color es el acento efectivo: si el perfil sigue al Tama, el del Tama
/// ajustado para leerse; si no, el elegido a mano.
UserCard cardFor(UserProfile profile, {String? tamaId, String? tamaColor}) => UserCard(
      displayName: profile.displayName,
      accentColor: profile.accentFollowsTama == true && tamaColor != null
          ? hexFromColor(accentForTama(tamaColor))
          : profile.accentColor.toUpperCase(),
      tamaId: tamaId,
    );

/// Ficha para guardar junto a un perfil nuevo. El Tama de perfil sale del
/// estado si ya ha llegado, y si no se lee: la ficha tiene que apuntar al
/// mismo Tama que `/users/{accountId}/tama` o las reglas la rechazan.
Future<UserCard> cardForProfile(Ref ref, UserProfile profile) async {
  final tamas = ref.read(tamasProvider);
  var tamaId = tamas.profileTamaId;
  if (!tamas.loaded) {
    final raw = await ref.read(backendProvider).read(
          '/users/${ref.read(sessionProvider).accountId}/tama',
          idToken: await ref.read(sessionProvider.notifier).freshToken(),
        );
    tamaId = raw is String ? raw : null;
  }
  return cardFor(profile, tamaId: tamaId, tamaColor: tamas.byId(tamaId)?.look.color);
}

/// Ficha para guardar junto a un cambio de Tama de perfil.
Future<UserCard> cardForTama(Ref ref, String? tamaId, String? tamaColor) async {
  var profile = ref.read(profileProvider).profile;
  final session = ref.read(sessionProvider);
  if (profile == null) {
    final raw = await ref.read(backendProvider).read(
          '/users/${session.accountId}/profile',
          idToken: await ref.read(sessionProvider.notifier).freshToken(),
        );
    profile = raw is Map
        ? UserProfile.fromJson(raw)
        : UserProfile(
            username: session.username,
            displayName: session.username,
            createdAt: DateTime.now(),
          );
  }
  return cardFor(profile, tamaId: tamaId, tamaColor: tamaColor);
}

/// Mantiene la ficha propia al dia.
///
/// Las escrituras que cambian nombre, color o Tama de perfil ya llevan la ficha
/// en la misma operacion. Esto cubre el resto: las cuentas de antes de que
/// existiera la ficha y el acento que sigue a un Tama cuyo color se ha editado
/// en otro equipo. Solo mira datos propios.
final cardKeeperProvider = Provider<void>((ref) {
  final account = ref.watch(sessionProvider.select((s) => s.accountId));
  if (account.isEmpty) return;
  final profile = ref.watch(profileProvider.select((p) => p.profile));
  final tamas = ref.watch(tamasProvider);
  final stored = ref.watch(cardOfProvider(account));
  if (profile == null || !tamas.loaded || stored.isLoading) return;

  final expected = cardFor(
    profile,
    tamaId: tamas.profileTamaId,
    tamaColor: tamas.profileTama?.look.color,
  );
  if (stored.valueOrNull == expected) return;

  // Un respiro: si hay una escritura con la ficha en camino, llega antes.
  final backend = ref.read(backendProvider);
  final session = ref.read(sessionProvider.notifier);
  final timer = Timer(const Duration(milliseconds: 1500), () async {
    try {
      await backend.write(
            '/users/$account/card',
            expected.toJson(),
            idToken: await session.freshToken(),
          );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido poner al dia la ficha ($e)');
    }
  });
  ref.onDispose(timer.cancel);
});
