// Ibasho — política portable de rutas para paquetes .ibasho.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'extension_error.dart';

final RegExp _portablePath = RegExp(r'^[A-Za-z0-9._/-]+$');
final RegExp _windowsDrive = RegExp(r'^[A-Za-z]:');
final RegExp _reservedWindowsName = RegExp(
  r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$',
  caseSensitive: false,
);

const Set<String> forbiddenExecutableExtensions = <String>{
  '.apk',
  '.aab',
  '.bat',
  '.class',
  '.cmd',
  '.com',
  '.cjs',
  '.dart',
  '.dex',
  '.dll',
  '.dylib',
  '.exe',
  '.ipa',
  '.jar',
  '.js',
  '.mjs',
  '.msi',
  '.php',
  '.ps1',
  '.py',
  '.rb',
  '.scr',
  '.sh',
  '.so',
  '.wasm',
};

String validatePackagePath(
  String raw, {
  required String subject,
  bool allowTrailingSlash = true,
}) {
  if (raw.isEmpty || raw.length > 256) {
    throw ExtensionException(
      ExtensionErrorCode.unsafePath,
      'Ruta vacía o demasiado larga.',
      subject: subject,
    );
  }
  if (raw.contains('\u0000') || raw.contains('\\')) {
    throw ExtensionException(
      ExtensionErrorCode.unsafePath,
      'Las rutas deben usar únicamente separadores POSIX.',
      subject: subject,
    );
  }
  if (raw.startsWith('/') || _windowsDrive.hasMatch(raw)) {
    throw ExtensionException(
      ExtensionErrorCode.unsafePath,
      'No se permiten rutas absolutas.',
      subject: subject,
    );
  }
  if (!_portablePath.hasMatch(raw)) {
    throw ExtensionException(
      ExtensionErrorCode.unsafePath,
      'IES 0.1 usa rutas ASCII portables para evitar colisiones Unicode entre plataformas.',
      subject: subject,
    );
  }

  var value = raw;
  if (allowTrailingSlash && value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  if (value.isEmpty) {
    throw ExtensionException(
      ExtensionErrorCode.unsafePath,
      'Ruta inválida.',
      subject: subject,
    );
  }

  final segments = value.split('/');
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      throw ExtensionException(
        ExtensionErrorCode.unsafePath,
        'La ruta contiene un segmento inseguro.',
        subject: subject,
      );
    }
    if (segment.endsWith('.')) {
      throw ExtensionException(
        ExtensionErrorCode.unsafePath,
        'Una ruta portable no puede terminar un segmento en punto.',
        subject: subject,
      );
    }
    if (_reservedWindowsName.hasMatch(segment)) {
      throw ExtensionException(
        ExtensionErrorCode.unsafePath,
        'La ruta usa un nombre reservado por Windows.',
        subject: subject,
      );
    }
  }
  return value;
}

bool hasForbiddenExecutableExtension(String path) {
  final lower = path.toLowerCase();
  for (final extension in forbiddenExecutableExtensions) {
    if (lower.endsWith(extension)) return true;
  }
  return false;
}
