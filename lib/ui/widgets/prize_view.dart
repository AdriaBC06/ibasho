// Ibasho — el dibujo de un premio suelto, sin Tama: en las tarjetas del
// pinball y en el Catalogo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../backend/backdrops.dart';
import '../../backend/gacha.dart';
import '../../backend/gacha_music.dart';
import '../../backend/prizes.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/tokens.dart';
import 'backdrop_art.dart';
import 'gacha_art.dart';

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

/// Cualquier premio del gacha por su clave: un gorro o un accesorio con su
/// dibujo, un fondo en miniatura o una musica con la nota de su categoria.
/// Sirve en las tarjetas del pinball y en el Catalogo, que en la 0.6.0 solo
/// sabian pintar lo que se pone un Tama.
class GachaPrizeView extends StatelessWidget {
  const GachaPrizeView(
    this.prizeKey, {
    super.key,
    this.size = 48,
    this.locked = false,
  });

  final String prizeKey;
  final double size;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final item = prizeItem(prizeKey);
    if (item != null) return PrizeView(item, size: size, locked: locked);

    final Widget art;
    if (backdropByKey(prizeKey) case final backdrop?) {
      art = Padding(
        padding: EdgeInsets.all(size * .08),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * .2),
          child: locked
              ? const ColoredBox(color: T.wellTop)
              : BackdropView(id: backdrop.id),
        ),
      );
    } else {
      art = CategoryArtView(GachaCategory.music, size: size);
    }
    return SizedBox(
      width: size,
      height: size,
      child: locked ? Opacity(opacity: .35, child: art) : art,
    );
  }
}

/// El nombre de un premio del gacha, sea de la categoria que sea.
String gachaPrizeName(L l, String key) {
  if (backdropByKey(key) != null) return l.backdropName(key);
  if (gachaMusicByKey(key) case final track?) return track.id;
  return l.prizeName(key);
}
