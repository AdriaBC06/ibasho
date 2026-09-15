// Ibasho — codigos de amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

/// Un codigo de amigo son doce digitos, `1234-5678-9012`, como en la 3DS.
///
/// Los once primeros salen de pasar el contador secuencial
/// `/system/friendCodeCounter` por una permutacion afin del espacio de once
/// digitos, `y = (a · n + b) mod 10^11`. Como `a` es coprimo con `10^11`, la
/// funcion es biyectiva: dos contadores distintos nunca dan el mismo codigo, y
/// no hace falta ir a la base a comprobar colisiones.
///
/// El duodecimo es un digito de control de Damm. Se prefiere a Luhn porque
/// Damm detecta **todos** los errores de un solo digito y **todas** las
/// transposiciones de dos digitos contiguos, que es lo que se falla al teclear
/// un codigo dictado de palabra.
abstract final class FriendCode {
  /// Digitos de un codigo, control incluido.
  static const int length = 12;

  /// Tamano del espacio de los once digitos permutados.
  static const int space = 100000000000;

  /// Multiplicador de la permutacion.
  ///
  /// `a` y `b` **no son secretos ni pretenden serlo**: estan en un repositorio
  /// publico. Un codigo de amigo no es una credencial, solo un identificador
  /// que no se tiene que poder adivinar probando el siguiente. Con estas
  /// constantes, dos contadores consecutivos dan codigos distintos en todas y
  /// cada una de las once posiciones: los digitos de `a` van del 1 al 8, asi
  /// que sumar `a` cambia cada cifra con o sin acarreo. Termina en 1 y no
  /// tiene ni doses ni cincos como factores, asi que es coprimo con `10^11`.
  static const int multiplier = 55683571461;

  /// Desplazamiento de la permutacion. Aleja el primer codigo de `0000…`.
  static const int offset = 27182818284;

  /// Codigo, sin guiones, del contador `n` (desde 1).
  static String forCounter(int n) {
    final m = BigInt.from(space);
    final y = (BigInt.from(multiplier) * BigInt.from(n) + BigInt.from(offset)) % m;
    final body = y.toString().padLeft(length - 1, '0');
    return '$body${dammDigit(body)}';
  }

  /// Contador que produjo un codigo valido, o `null` si no lo es. Solo lo usan
  /// las pruebas, para demostrar que la permutacion es reversible.
  static int? counterOf(String code) {
    final digits = normalize(code);
    if (digits == null || !isValid(digits)) return null;
    final m = BigInt.from(space);
    final inverse = BigInt.from(multiplier).modInverse(m);
    final y = BigInt.parse(digits.substring(0, length - 1));
    return ((y - BigInt.from(offset)) * inverse % m).toInt();
  }

  /// Tabla de la cuasigrupo de orden 10 de H. Michael Damm (2004): totalmente
  /// antisimetrica y con ceros en la diagonal.
  static const List<List<int>> _damm = <List<int>>[
    [0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
    [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
    [4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
    [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
    [6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
    [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
    [5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
    [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
    [9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
    [2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
  ];

  static int _interim(String digits) {
    var state = 0;
    for (final unit in digits.codeUnits) {
      state = _damm[state][unit - 0x30];
    }
    return state;
  }

  /// Digito de control de Damm para una ristra de digitos.
  static int dammDigit(String digits) => _interim(digits);

  /// Doce digitos cuyo control cuadra. Un codigo con un digito mal escrito
  /// no pasa de aqui, y por eso se rechaza sin tocar la red.
  static bool isValid(String digits) =>
      digits.length == length &&
      RegExp(r'^[0-9]+$').hasMatch(digits) &&
      _interim(digits) == 0;

  /// Lo que haya escrito o pegado la persona, sin guiones ni espacios. `null`
  /// si trae algo que no es un digito.
  static String? normalize(String input) {
    final stripped = input.replaceAll(RegExp(r'[\s\-‐‑‒–—−]'), '');
    if (!RegExp(r'^[0-9]*$').hasMatch(stripped)) return null;
    return stripped;
  }

  /// `123456789012` → `1234-5678-9012`. Acepta codigos a medias.
  static String format(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write('-');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
