// Ibasho — pruebas de SemVer para compatibilidad IES.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/extensions/extensions.dart';

void main() {
  test('ordena prerelease antes que release', () {
    final pre = SemVersion.parse('1.0.0-rc.1');
    final stable = SemVersion.parse('1.0.0');
    expect(pre < stable, isTrue);
  });

  test('ignora build metadata para precedencia', () {
    expect(SemVersion.parse('1.0.0+abc'), SemVersion.parse('1.0.0+xyz'));
  });

  test('caret ^1.0 acepta 1.x pero no 2.0', () {
    final range = ApiRequirement.parse('^1.0');
    expect(range.allows(const SemVersion(1, 0, 0)), isTrue);
    expect(range.allows(const SemVersion(1, 9, 9)), isTrue);
    expect(range.allows(const SemVersion(2, 0, 0)), isFalse);
  });

  test('caret ^0.2 queda dentro de 0.2.x', () {
    final range = ApiRequirement.parse('^0.2');
    expect(range.allows(const SemVersion(0, 2, 9)), isTrue);
    expect(range.allows(const SemVersion(0, 3, 0)), isFalse);
  });
}
