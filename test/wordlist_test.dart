// Ibasho — el alfabeto de la frase de respaldo no se puede tocar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/crypto/wordlist.dart';

void main() {
  test('son exactamente 512 palabras', () {
    expect(backupWordlist.length, 512);
  });

  test('estan ordenadas alfabeticamente', () {
    for (var i = 1; i < backupWordlist.length; i++) {
      expect(
        backupWordlist[i - 1].compareTo(backupWordlist[i]) < 0,
        isTrue,
        reason: '${backupWordlist[i - 1]} deberia ir antes que '
            '${backupWordlist[i]}',
      );
    }
  });

  test('cada palabra son solo letras a-z, de 3 a 8', () {
    final pattern = RegExp(r'^[a-z]{3,8}$');
    for (final word in backupWordlist) {
      expect(pattern.hasMatch(word), isTrue, reason: word);
    }
  });

  test('las 512 palabras son distintas entre si', () {
    expect(backupWordlist.toSet().length, backupWordlist.length);
  });

  test('las cuatro primeras letras de cada palabra son unicas', () {
    // Dos palabras "colisionan" si coinciden en los primeros
    // min(len(a), len(b), 4) caracteres: asi una palabra de 3 letras
    // bloquea a cualquier otra que empiece igual (regla del autocompletado).
    for (var i = 0; i < backupWordlist.length; i++) {
      for (var j = i + 1; j < backupWordlist.length; j++) {
        final a = backupWordlist[i];
        final b = backupWordlist[j];
        final k = [a.length, b.length, 4].reduce((x, y) => x < y ? x : y);
        expect(
          a.substring(0, k) == b.substring(0, k),
          isFalse,
          reason: '$a y $b comparten prefijo',
        );
      }
    }
  });
}
