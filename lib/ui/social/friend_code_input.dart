// Ibasho — entrada del codigo de amigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';

import '../../core/friend_code.dart';

/// Deja solo digitos, como mucho doce, y pone los guiones solo: se puede
/// escribir seguido o pegar el codigo con guiones, espacios o sin nada.
///
/// El cursor se queda detras del mismo digito en el que estaba, aunque se
/// hayan anadido o quitado guiones delante.
class FriendCodeFormatter extends TextInputFormatter {
  const FriendCodeFormatter();

  static final RegExp _nonDigit = RegExp(r'\D');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(_nonDigit, '');
    if (digits.length > FriendCode.length) digits = digits.substring(0, FriendCode.length);
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final before = newValue.text
        .substring(0, end)
        .replaceAll(_nonDigit, '')
        .length
        .clamp(0, digits.length);
    final formatted = FriendCode.format(digits);
    final offset = before + (before > 0 ? (before - 1) ~/ 4 : 0);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset.clamp(0, formatted.length)),
    );
  }
}
