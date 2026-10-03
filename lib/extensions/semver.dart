// Ibasho — SemVer mínimo para compatibilidad de extensiones.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'extension_error.dart';

final RegExp _semverPattern = RegExp(
  r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
  r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
  r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$',
);

class SemVersion implements Comparable<SemVersion> {
  const SemVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease = const <String>[],
    this.build = const <String>[],
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;
  final List<String> build;

  static SemVersion? tryParse(String raw) {
    final match = _semverPattern.firstMatch(raw.trim());
    if (match == null) return null;
    return SemVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: match.group(4)?.split('.') ?? const <String>[],
      build: match.group(5)?.split('.') ?? const <String>[],
    );
  }

  static SemVersion parse(String raw, {String? subject}) {
    final parsed = tryParse(raw);
    if (parsed == null) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Versión SemVer inválida: $raw',
        subject: subject,
      );
    }
    return parsed;
  }

  @override
  int compareTo(SemVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < length; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;
      final left = preRelease[i];
      final right = other.preRelease[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        final result = leftNumber.compareTo(rightNumber);
        if (result != 0) return result;
      } else if (leftNumber != null) {
        return -1;
      } else if (rightNumber != null) {
        return 1;
      } else {
        final result = left.compareTo(right);
        if (result != 0) return result;
      }
    }
    return 0;
  }

  bool operator <(SemVersion other) => compareTo(other) < 0;
  bool operator <=(SemVersion other) => compareTo(other) <= 0;
  bool operator >(SemVersion other) => compareTo(other) > 0;
  bool operator >=(SemVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVersion && compareTo(other) == 0;

  @override
  int get hashCode =>
      Object.hashAll(<Object>[major, minor, patch, ...preRelease]);

  @override
  String toString() {
    final pre = preRelease.isEmpty ? '' : '-${preRelease.join('.')}';
    final meta = build.isEmpty ? '' : '+${build.join('.')}';
    return '$major.$minor.$patch$pre$meta';
  }
}

/// El MVP acepta únicamente rangos exactos y caret (`^1.0`, `^1.2.3`).
/// Requisitos desconocidos fallan cerrados, en vez de intentar adivinarlos.
class ApiRequirement {
  const ApiRequirement._({
    required this.raw,
    required this.minimum,
    required this.maximumExclusive,
  });

  final String raw;
  final SemVersion minimum;
  final SemVersion maximumExclusive;

  static ApiRequirement parse(String raw) {
    final value = raw.trim();
    if (value.startsWith('^')) {
      final body = value.substring(1);
      final parts = body.split('.');
      if (parts.length != 2 && parts.length != 3) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Rango ibashoApi no soportado: $raw',
          subject: 'compatibility.ibashoApi',
        );
      }
      final major = int.tryParse(parts[0]);
      final minor = int.tryParse(parts[1]);
      final patch = parts.length == 3 ? int.tryParse(parts[2]) : 0;
      if (major == null ||
          minor == null ||
          patch == null ||
          major < 0 ||
          minor < 0 ||
          patch < 0) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Rango ibashoApi inválido: $raw',
          subject: 'compatibility.ibashoApi',
        );
      }
      final minimum = SemVersion(major, minor, patch);
      final maximum = major > 0
          ? SemVersion(major + 1, 0, 0)
          : minor > 0
          ? SemVersion(0, minor + 1, 0)
          : SemVersion(0, 0, patch + 1);
      return ApiRequirement._(
        raw: value,
        minimum: minimum,
        maximumExclusive: maximum,
      );
    }

    final exact = SemVersion.tryParse(value);
    if (exact == null) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Rango ibashoApi no soportado: $raw',
        subject: 'compatibility.ibashoApi',
      );
    }
    return ApiRequirement._(
      raw: value,
      minimum: exact,
      maximumExclusive: SemVersion(
        exact.major,
        exact.minor,
        exact.patch + 1,
        preRelease: const <String>['0'],
      ),
    );
  }

  bool allows(SemVersion version) =>
      version >= minimum && version < maximumExclusive;
}
