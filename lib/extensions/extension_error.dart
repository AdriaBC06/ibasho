// Ibasho — errores del sistema de extensiones.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

enum ExtensionErrorCode {
  invalidManifest,
  invalidPackage,
  unsafePath,
  unsupportedEntry,
  sizeLimitExceeded,
  tooManyEntries,
  duplicateEntry,
  forbiddenCapability,
  unknownCapability,
  incompatibleHost,
  unsupportedExtensionType,
  integrityMismatch,
  alreadyInstalled,
  downgradeBlocked,
  corruptIndex,
  ioFailure,
}

class ExtensionException implements Exception {
  const ExtensionException(this.code, this.message, {this.subject, this.cause});

  final ExtensionErrorCode code;
  final String message;
  final String? subject;
  final Object? cause;

  @override
  String toString() {
    final where = subject == null ? '' : ' [$subject]';
    return 'ExtensionException(${code.name})$where: $message';
  }
}
