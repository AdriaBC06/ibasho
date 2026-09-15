// Ibasho — version de la app y comparacion de versiones.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// La version de esta build. Tiene que coincidir con `version:` de
/// `pubspec.yaml` (lo comprueba `test/update_gate_test.dart`).
const String appVersion = '0.3.0';

/// Una version `mayor.menor.parche`.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp pattern = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$');

  /// `null` si no tiene la forma `1.2.3`.
  static AppVersion? tryParse(String raw) {
    final m = pattern.firstMatch(raw.trim());
    if (m == null) return null;
    return AppVersion(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  static final AppVersion current = tryParse(appVersion)!;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) => other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
