// Ibasho — errores del backend, ya traducidos a causas de dominio.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

/// Motivos por los que una operacion contra el backend puede fallar.
///
/// La interfaz nunca ve un codigo de Identity Toolkit ni un status HTTP: solo
/// uno de estos.
enum IbashoFailure {
  network,
  invalidCredentials,
  accountDisabled,
  notAllowed,
  tooManyAttempts,
  permissionDenied,
  weakPassword,
  usernameTaken,
  tokenExpired,
  unknown,
}

class IbashoException implements Exception {
  const IbashoException(this.failure, [this.detail]);

  final IbashoFailure failure;
  final String? detail;

  @override
  String toString() =>
      'IbashoException(${failure.name}${detail == null ? '' : ': $detail'})';
}
