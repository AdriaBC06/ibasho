// Ibasho — codigos de amigo: permutacion, control de Damm y formato.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/core/friend_code.dart';

void main() {
  test('las constantes forman una permutacion del espacio de once digitos', () {
    final a = BigInt.from(FriendCode.multiplier);
    expect(a.gcd(BigInt.from(FriendCode.space)), BigInt.one);
    for (final n in [1, 2, 3, 10, 999, 123456, 99999999]) {
      final code = FriendCode.forCounter(n);
      expect(code.length, 12);
      expect(FriendCode.isValid(code), isTrue, reason: code);
      expect(FriendCode.counterOf(code), n, reason: 'la permutacion se deshace');
    }
  });

  test('dos codigos consecutivos no se parecen: cambian las once cifras', () {
    // Criterio de aceptacion 3.
    final seen = <String>{};
    var previous = FriendCode.forCounter(1);
    seen.add(previous);
    for (var n = 2; n <= 20000; n++) {
      final code = FriendCode.forCounter(n);
      expect(seen.add(code), isTrue, reason: 'nunca se repite');
      var same = 0;
      for (var i = 0; i < 11; i++) {
        if (code[i] == previous[i]) same++;
      }
      expect(same, 0, reason: '$previous → $code');
      previous = code;
    }
  });

  test('mirar el tuyo no dice cual es el siguiente: sumar uno da un codigo invalido o ajeno', () {
    for (var n = 1; n <= 2000; n++) {
      final mine = FriendCode.forCounter(n);
      final next = FriendCode.forCounter(n + 1);
      final bumped = (BigInt.parse(mine) + BigInt.one).toString().padLeft(12, '0');
      expect(bumped == next, isFalse);
      // Incrementar el cuerpo y recalcular el control tampoco lleva al siguiente.
      final body = (BigInt.parse(mine.substring(0, 11)) + BigInt.one)
          .toString()
          .padLeft(11, '0');
      expect('$body${FriendCode.dammDigit(body)}' == next, isFalse);
    }
  });

  test('Damm detecta todo error de un digito y toda transposicion contigua', () {
    for (var n = 1; n <= 400; n++) {
      final code = FriendCode.forCounter(n);
      for (var i = 0; i < 12; i++) {
        for (var d = 0; d <= 9; d++) {
          if ('$d' == code[i]) continue;
          final typo = code.replaceRange(i, i + 1, '$d');
          expect(FriendCode.isValid(typo), isFalse, reason: '$code → $typo');
        }
        if (i < 11 && code[i] != code[i + 1]) {
          final swapped = code.replaceRange(i, i + 2, '${code[i + 1]}${code[i]}');
          expect(FriendCode.isValid(swapped), isFalse, reason: '$code → $swapped');
        }
      }
    }
  });

  test('formato y normalizacion aceptan el codigo con o sin guiones', () {
    final code = FriendCode.forCounter(42);
    final pretty = FriendCode.format(code);
    expect(pretty, matches(RegExp(r'^\d{4}-\d{4}-\d{4}$')));
    expect(FriendCode.normalize(pretty), code);
    expect(FriendCode.normalize(' ${code.substring(0, 4)} ${code.substring(4)} '), code);
    expect(FriendCode.normalize('1234–5678—9012'), '123456789012');
    expect(FriendCode.normalize('1234-abcd'), isNull);
    expect(FriendCode.format('12345'), '1234-5');
    expect(FriendCode.isValid(code.substring(0, 11)), isFalse);
  });
}
