// Ibasho — política de activación de extensiones.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'extension_error.dart';
import 'manifest.dart';
import 'semver.dart';

class ExtensionHostProfile {
  const ExtensionHostProfile({
    required this.ibashoVersion,
    this.extensionApiVersion = const SemVersion(1, 0, 0),
  });

  final SemVersion ibashoVersion;
  final SemVersion extensionApiVersion;

  void requireCompatible(ExtensionManifest manifest) {
    final compatibility = manifest.compatibility;
    if (ibashoVersion < compatibility.minimumIbasho) {
      throw ExtensionException(
        ExtensionErrorCode.incompatibleHost,
        'La extensión requiere Ibasho ${compatibility.minimumIbasho} o posterior.',
        subject: manifest.id,
      );
    }
    final maximum = compatibility.maximumIbasho;
    if (maximum != null && ibashoVersion > maximum) {
      throw ExtensionException(
        ExtensionErrorCode.incompatibleHost,
        'La extensión declara compatibilidad máxima con Ibasho $maximum.',
        subject: manifest.id,
      );
    }
    if (!compatibility.ibashoApi.allows(extensionApiVersion)) {
      throw ExtensionException(
        ExtensionErrorCode.incompatibleHost,
        'La extensión requiere API ${compatibility.ibashoApi.raw}; el host ofrece $extensionApiVersion.',
        subject: manifest.id,
      );
    }
  }
}

class ExtensionInstallPolicy {
  const ExtensionInstallPolicy({
    this.allowedTypes = const <ExtensionType>{ExtensionType.contentPack},
    this.allowRequiredPermissions = false,
    this.allowOptionalPermissions = false,
    this.allowDowngrade = false,
  });

  final Set<ExtensionType> allowedTypes;
  final bool allowRequiredPermissions;
  final bool allowOptionalPermissions;
  final bool allowDowngrade;

  void validate(ExtensionManifest manifest) {
    if (!allowedTypes.contains(manifest.type)) {
      throw ExtensionException(
        ExtensionErrorCode.unsupportedExtensionType,
        'El runtime 0.1 solo activa tipos explícitamente permitidos.',
        subject: manifest.type.wireName,
      );
    }
    if (!allowRequiredPermissions && manifest.permissions.isNotEmpty) {
      throw ExtensionException(
        ExtensionErrorCode.forbiddenCapability,
        'El MVP no activa extensiones con permisos obligatorios.',
        subject: manifest.id,
      );
    }
    if (!allowOptionalPermissions && manifest.optionalPermissions.isNotEmpty) {
      throw ExtensionException(
        ExtensionErrorCode.forbiddenCapability,
        'El MVP no activa extensiones con permisos opcionales.',
        subject: manifest.id,
      );
    }
  }
}
