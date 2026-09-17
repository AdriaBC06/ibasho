// Ibasho — la frase de respaldo: 12 palabras que abren tu historial.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later


import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'random.dart';
import 'wordlist.dart';

/// Palabras de una frase.
const int mnemonicWords = 12;

/// Bits que aporta cada palabra: 512 opciones, 9 bits.
const int _bitsPerWord = 9;

/// Bytes de azar de verdad: 104 bits.
const int mnemonicEntropyBytes = 13;

/// Los cuatro bits que sobran son suma de comprobacion: una errata al teclear
/// se detecta 15 de cada 16 veces, que es lo que hace falta para no dejar a
/// nadie peleandose con un "no funciona" sin pista.
const int _checksumBits = mnemonicWords * _bitsPerWord - mnemonicEntropyBytes * 8;

/// Por que no vale una frase.
enum MnemonicFailure {
  /// No hay doce palabras.
  wordCount,

  /// Alguna palabra no esta en la lista.
  unknownWord,

  /// Las doce estan en la lista, pero la suma no cuadra: hay una cambiada de
  /// sitio o mal copiada.
  checksum,
}

/// Una frase mal escrita, con el sitio del fallo para poder señalarlo.
@immutable
class MnemonicError implements Exception {
  const MnemonicError(this.failure, {this.index, this.word});

  final MnemonicFailure failure;

  /// Posicion de la palabra que falla, de 0 a 11.
  final int? index;

  /// Lo que se escribio ahi.
  final String? word;

  @override
  String toString() => 'MnemonicError($failure, $index, $word)';
}

/// Una frase de respaldo nueva.
List<String> generateMnemonic() => mnemonicFromEntropy(randomBytes(mnemonicEntropyBytes));

/// Las doce palabras de una entropia dada. Determinista: el mismo azar da
/// siempre la misma frase, y por eso se puede probar.
List<String> mnemonicFromEntropy(Uint8List entropy) {
  assert(entropy.length == mnemonicEntropyBytes);
  final bits = <bool>[
    for (final byte in entropy)
      for (var i = 7; i >= 0; i--) (byte >> i) & 1 == 1,
  ];
  final digest = sha256.convert(entropy).bytes;
  for (var i = 0; i < _checksumBits; i++) {
    bits.add((digest[i ~/ 8] >> (7 - i % 8)) & 1 == 1);
  }

  return <String>[
    for (var w = 0; w < mnemonicWords; w++)
      backupWordlist[_readBits(bits, w * _bitsPerWord, _bitsPerWord)],
  ];
}

/// La entropia de una frase, o `MnemonicError` si no es valida.
///
/// Acepta lo que se teclea de verdad: mayusculas, tildes que la lista no
/// lleva, espacios de mas, saltos de linea al pegar y palabras cortadas a
/// partir de la cuarta letra, que ya identifica a una sola.
Uint8List entropyFromMnemonic(String phrase) {
  final words = normalizeMnemonic(phrase);
  if (words.length != mnemonicWords) {
    throw MnemonicError(MnemonicFailure.wordCount);
  }

  final bits = <bool>[];
  for (var i = 0; i < words.length; i++) {
    final index = indexOfWord(words[i]);
    if (index < 0) {
      throw MnemonicError(MnemonicFailure.unknownWord, index: i, word: words[i]);
    }
    for (var b = _bitsPerWord - 1; b >= 0; b--) {
      bits.add((index >> b) & 1 == 1);
    }
  }

  final entropy = Uint8List(mnemonicEntropyBytes);
  for (var i = 0; i < mnemonicEntropyBytes; i++) {
    entropy[i] = _readBits(bits, i * 8, 8);
  }

  final digest = sha256.convert(entropy).bytes;
  for (var i = 0; i < _checksumBits; i++) {
    final expected = (digest[i ~/ 8] >> (7 - i % 8)) & 1 == 1;
    if (bits[mnemonicEntropyBytes * 8 + i] != expected) {
      throw const MnemonicError(MnemonicFailure.checksum);
    }
  }
  return entropy;
}

/// Parte la frase en palabras normalizadas, sin comprobar nada mas. La usa
/// tambien la pantalla, para ir marcando lo que ya esta bien escrito.
List<String> normalizeMnemonic(String phrase) => phrase
    .split(RegExp(r'[\s,]+'))
    .map(normalizeWord)
    .where((w) => w.isNotEmpty)
    .toList(growable: false);

/// Una palabra tal como la entiende la lista: minusculas, sin tildes y sin
/// nada que no sea una letra.
String normalizeWord(String raw) {
  final lower = raw.toLowerCase().trim();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final plain = _accents[ch] ?? ch;
    if (plain.codeUnitAt(0) >= 0x61 && plain.codeUnitAt(0) <= 0x7a) {
      out.write(plain);
    }
  }
  return out.toString();
}

/// Posicion de una palabra en la lista, o -1.
///
/// Con cuatro letras o mas basta: la lista garantiza que ese prefijo es unico,
/// asi que "cami" encuentra "camino" y quien escribe a mano no tiene que
/// acertar la palabra entera.
int indexOfWord(String word) {
  if (word.length < 3) return -1;
  final exact = _binarySearch(word);
  if (exact >= 0) return exact;
  if (word.length < 4) return -1;
  final prefix = word.substring(0, 4);
  var low = 0;
  var high = backupWordlist.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final candidate = backupWordlist[mid];
    final head = candidate.length < 4 ? candidate : candidate.substring(0, 4);
    final cmp = head.compareTo(prefix);
    if (cmp == 0) return candidate.startsWith(word) ? mid : -1;
    if (cmp < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

int _binarySearch(String word) {
  var low = 0;
  var high = backupWordlist.length - 1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    final cmp = backupWordlist[mid].compareTo(word);
    if (cmp == 0) return mid;
    if (cmp < 0) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

int _readBits(List<bool> bits, int offset, int count) {
  var value = 0;
  for (var i = 0; i < count; i++) {
    value = (value << 1) | (bits[offset + i] ? 1 : 0);
  }
  return value;
}

/// Lo que puede teclear alguien que escribe en castellano con el teclado
/// puesto. La lista no tiene tildes ni eñes, asi que se doblan a su letra.
const Map<String, String> _accents = <String, String>{
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};
