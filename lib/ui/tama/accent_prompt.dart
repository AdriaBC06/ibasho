// Ibasho — preguntar antes de tocar un acento elegido a mano.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/accent_sync.dart';
import '../../state/providers.dart';
import '../../theme/menu_theme.dart';
import '../widgets/overlays.dart';

/// El Tama de perfil tiene un color nuevo: sincroniza el acento si toca, o
/// pregunta si el acento se eligio a mano.
///
/// Solo hay que llamarlo cuando el color ha cambiado de verdad (o cuando el
/// Tama de perfil es otro): si no, alguien con un acento propio recibiria la
/// pregunta cada vez que guarda cualquier cosa.
Future<void> reconcileAccentWithTama(
  BuildContext context,
  WidgetRef ref,
  String tamaHex,
) async {
  final profile = ref.read(profileProvider).profile;
  if (profile == null) return;
  switch (decideAccentSync(profile, tamaHex)) {
    case AccentSync.none:
      return;
    case AccentSync.follow:
      await ref.read(profileProvider.notifier).save(followTama(profile, tamaHex));
    case AccentSync.ask:
      final l = L.of(context)!;
      final yes = await askConfirmation(
        context,
        title: l.accentResyncTitle,
        body: l.accentResyncBody,
        confirmLabel: l.accentResyncYes,
        cancelLabel: l.accentResyncNo,
        width: 640,
      );
      if (!yes) return;
      final latest = ref.read(profileProvider).profile ?? profile;
      await ref.read(profileProvider.notifier).save(followTama(latest, tamaHex));
  }
}

/// Pone un Tama en el perfil y, si cambia el color, sincroniza o pregunta por
/// el acento. Devuelve `true` si el servidor lo acepto.
Future<bool> putTamaOnProfile(BuildContext context, WidgetRef ref, Tama tama) async {
  final previous = ref.read(tamasProvider).profileTama?.look.color;
  final ok = await ref.read(tamasProvider.notifier).setProfile(tama.id);
  if (!context.mounted) return ok;
  if (!ok) {
    AudioService.instance.play(Sfx.error);
    showIbashoToast(context, L.of(context)!.tamaSaveError, isError: true);
    return false;
  }
  if (previous != tama.look.color) {
    await reconcileAccentWithTama(context, ref, tama.look.color);
  }
  return true;
}

/// Se acaba de poner el tema [backdropId]: si trae otro acento y el acento
/// aun no sigue al tema, pregunta si debe seguirlo. Quien ya lo sigue no
/// recibe la pregunta: el acento cambia solo con el tema.
Future<void> askAccentForTheme(
  BuildContext context,
  WidgetRef ref,
  String backdropId,
) async {
  final theme = menuThemeFor(backdropId);
  if (theme == null) return;
  if (ref.read(preferencesProvider).accentFollowsTheme) return;
  if (ref.read(accentProvider) == theme.accent) return;
  final l = L.of(context)!;
  final yes = await askConfirmation(
    context,
    title: l.themeAccentTitle,
    body: l.themeAccentBody(l.backdropName('bg_$backdropId')),
    confirmLabel: l.themeAccentYes,
    cancelLabel: l.themeAccentNo,
    width: 640,
  );
  if (!yes) return;
  await ref.read(preferencesProvider.notifier).setAccentFollowsTheme(true);
}
