// Ibasho — textos traducidos de las pistas de musica.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../audio/audio_service.dart';
import '../l10n/gen/app_localizations.dart';

String describeTrack(L l, MusicTrack track) => switch (track) {
      MusicTrack.plaza => l.trackPlaza,
      MusicTrack.bossa => l.trackBossa,
      MusicTrack.hanami => l.trackHanami,
      MusicTrack.sumi => l.trackSumi,
      MusicTrack.calma => l.trackCalma,
      MusicTrack.aurora => l.trackAurora,
      MusicTrack.brisa => l.trackBrisa,
      MusicTrack.noche => l.trackNoche,
    };
