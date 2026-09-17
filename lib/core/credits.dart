// Ibasho — registro de creditos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../l10n/gen/app_localizations.dart';

/// Una obra de terceros —o propia— usada por Ibasho.
///
/// Esta lista es la misma que hay en `CREDITS.md`, en la raiz del repositorio.
/// Si se anade un asset, se tocan los dos sitios.
///
/// Titulos, autores y licencias son nombres propios y no se traducen; las
/// notas descriptivas si, y por eso llegan como funcion del catalogo.
class CreditEntry {
  const CreditEntry({
    required this.title,
    required this.author,
    required this.license,
    required this.url,
    this.note,
  });

  final String title;
  final String author;
  final String license;
  final String url;
  final String Function(L l)? note;
}

const String _me = 'Adrià Bonnin Catalán';

String _zenKaku(L l) => l.creditNoteZenKaku;
String _rounded(L l) => l.creditNoteRounded;
String _ownMusic(L l) => l.creditNoteOwnMusic;
String _ownSfx(L l) => l.creditNoteOwnSfx;
String _downloaded(L l) => l.creditNoteDownloaded;
String _timezone(L l) => l.creditNoteTimezone;

const List<CreditEntry> fontCredits = <CreditEntry>[
  CreditEntry(
    title: 'Zen Kaku Gothic New',
    author: 'Yoshimichi Ohira',
    license: 'SIL Open Font License 1.1',
    url: 'https://fonts.google.com/specimen/Zen+Kaku+Gothic+New',
    note: _zenKaku,
  ),
  CreditEntry(
    title: 'M PLUS Rounded 1c',
    author: 'Coji Morishita, The M+ Fonts Project',
    license: 'SIL Open Font License 1.1',
    url: 'https://github.com/coz-m/MPLUS_FONTS',
    note: _rounded,
  ),
];

const List<CreditEntry> audioCredits = <CreditEntry>[
  CreditEntry(
    title: 'plaza · calma · aurora · brisa · noche',
    author: _me,
    license: 'CC0 1.0',
    url: 'tool/gen_audio.py',
    note: _ownMusic,
  ),
  CreditEntry(
    title: 'tick · open · back · error · chime',
    author: _me,
    license: 'CC0 1.0',
    url: 'tool/gen_audio.py',
    note: _ownSfx,
  ),
  CreditEntry(
    title: 'Bossa Nova',
    author: 'Joth',
    license: 'CC0 1.0',
    url: 'https://opengameart.org/content/bossa-nova',
    note: _downloaded,
  ),
];

const List<CreditEntry> softwareCredits = <CreditEntry>[
  CreditEntry(
    title: 'Flutter',
    author: 'The Flutter Authors',
    license: 'BSD 3-Clause',
    url: 'https://flutter.dev',
  ),
  CreditEntry(
    title: 'Riverpod',
    author: 'Remi Rousselet',
    license: 'MIT',
    url: 'https://riverpod.dev',
  ),
  CreditEntry(
    title: 'audioplayers',
    author: 'Blue Fire',
    license: 'MIT',
    url: 'https://pub.dev/packages/audioplayers',
  ),
  CreditEntry(
    title: 'pointycastle',
    author: 'The Legion of the Bouncy Castle',
    license: 'MIT',
    url: 'https://pub.dev/packages/pointycastle',
  ),
  CreditEntry(
    title: 'timezone',
    author: 'timezone project authors',
    license: 'BSD 2-Clause',
    url: 'https://pub.dev/packages/timezone',
    note: _timezone,
  ),
  CreditEntry(
    title: 'url_launcher',
    author: 'The Flutter Authors',
    license: 'BSD 3-Clause',
    url: 'https://pub.dev/packages/url_launcher',
  ),
  CreditEntry(
    title: 'flutter_secure_storage',
    author: 'Julian Steenbakker',
    license: 'BSD 3-Clause',
    url: 'https://pub.dev/packages/flutter_secure_storage',
  ),
  CreditEntry(
    title: 'http · intl · crypto · path_provider',
    author: 'The Dart and Flutter Authors',
    license: 'BSD 3-Clause',
    url: 'https://pub.dev',
  ),
];
