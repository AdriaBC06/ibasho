// Ibasho — puente de arranque seguro para contenido Kōbō.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import '../audio/audio_service.dart';
import 'addon_manager.dart';
import 'content_registry.dart';

/// Restaura la música local de Kōbō antes de montar la interfaz.
///
/// Una pista de extensión nunca entra en la biblioteca remota de la cuenta:
/// se resuelve contra la versión activa instalada en este dispositivo.
Future<void> restoreInitialExtensionMusic(String preferenceId) async {
  if (!preferenceId.startsWith('ext:')) {
    await AudioService.instance.setTrack(preferenceId);
    return;
  }

  final registry = await ExtensionContentLoader(
    await AddonManager.open(),
  ).load();
  final track = registry.musicByPreferenceId(preferenceId);
  if (track == null) {
    await AudioService.instance.setMenuFile(null);
    await AudioService.instance.setTrack(MusicTrack.fallback.id);
    return;
  }

  // El reproductor conserva una pista nativa de respaldo, pero el archivo
  // local de Kōbō manda mientras la extensión siga disponible.
  await AudioService.instance.setTrack(MusicTrack.fallback.id);
  await AudioService.instance.setMenuFile(track.filePath);
}
