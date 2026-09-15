// Ibasho — punto de entrada.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ibasho is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version. See the LICENSE file at the root of this repository.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'audio/audio_service.dart';
import 'state/providers.dart';
import 'storage/secure_store.dart';
import 'storage/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Nombres de mes y de dia en los dos idiomas, sin pedir nada por red.
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  final settingsStore = await SettingsStore.open();
  final preferences = await settingsStore.load();
  final secureStore = await openSecureStore();

  await AudioService.instance.init();
  await AudioService.instance.setTrack(preferences.musicTrack);
  await AudioService.instance.setMusicVolume(preferences.musicVolume);
  await AudioService.instance.setEffectsVolume(preferences.effectsVolume);

  runApp(
    ProviderScope(
      overrides: [
        secureStoreProvider.overrideWithValue(secureStore),
        settingsStoreProvider.overrideWithValue(settingsStore),
        initialPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const IbashoApp(),
    ),
  );
}
