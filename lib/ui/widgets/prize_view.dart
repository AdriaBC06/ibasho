// Ibasho — el dibujo de un premio suelto, sin Tama: en las tarjetas del
// pinball y en el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../backend/prizes.dart';
import '../../theme/tokens.dart';

/// [item] en un cuadrado de [size]. Si [locked], es la silueta de lo que aun
/// no se tiene.
class PrizeView extends StatelessWidget {
  const PrizeView(this.item, {super.key, this.size = 48, this.locked = false});

  final PrizeItem item;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final filter = locked ? ColorFilter.mode(T.inkSoft.withValues(alpha: .45), BlendMode.srcIn) : null;
    Widget art(String asset) => SvgPicture.asset(asset, width: size, height: size, colorFilter: filter);
    final front = item.frontAsset;
    return SizedBox(
      width: size,
      height: size,
      child: front == null ? art(item.asset) : Stack(children: [art(item.asset), art(front)]),
    );
  }
}
