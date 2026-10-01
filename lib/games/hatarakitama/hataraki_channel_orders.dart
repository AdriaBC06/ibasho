// Ibasho — canal de Hatarakitama: el tablón de encargos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

part of 'hataraki_channel.dart';

/// Un encargo en el tablón: lo que pide (con lo que hay), lo que paga y, el
/// grande, su ticket.
class _OrderTile extends StatelessWidget {
  const _OrderTile({
    super.key,
    required this.game,
    required this.order,
    required this.width,
    required this.height,
    required this.selected,
    required this.onPressed,
  });

  final HState game;
  final HOrder order;
  final double width;
  final double height;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final o = order;
    final ready =
        !o.done && o.wants.entries.every((e) => game.count(e.key) >= e.value);
    final first = o.wants.entries.first;
    return SlotTile(
      width: width,
      height: height,
      selected: selected,
      semanticLabel: o.big ? l.hatarakiOrderBig : l.hatarakiOrder,
      onPressed: onPressed,
      child: Stack(
        children: [
          Opacity(
            opacity: o.done ? .5 : 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
              child: Column(
                children: [
                  Expanded(
                    child: FittedBox(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in o.wants.keys.take(3))
                            HatarakiItemIcon(
                              id,
                              size: o.wants.length > 1 ? 36 : 48,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    o.big
                        ? l.hatarakiOrderBig
                        : '${_compact(game.count(first.key))}/${first.value}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.micro.copyWith(
                      color: !o.big && game.count(first.key) < first.value
                          ? T.warn
                          : Ty.ink,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const ArtIconView(ArtIcon.ginmon, size: 14),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _compact(o.money),
                          maxLines: 1,
                          style: Ty.numeral(
                            14,
                            color: skin.accentDeep,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (o.big) ...[
                        const SizedBox(width: 4),
                        const ArtIconView(ArtIcon.ticketGachaken, size: 16),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (o.done || ready)
            Positioned(
              right: 6,
              top: 6,
              child: GlyphIcon(
                o.done ? Glyph.check : Glyph.plus,
                size: 16,
                color: o.done ? T.correct : skin.accentDeep,
                strokeWidth: 2.8,
              ),
            ),
        ],
      ),
    );
  }
}

/// La ficha de un encargo: lo que pide, de dónde sale y lo que paga.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.game,
    required this.order,
    required this.ticketToday,
  });

  final HState game;
  final HOrder order;

  /// Si el ticket del gran encargo ya se ha cobrado hoy.
  final bool ticketToday;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final o = order;
    final missing = [
      for (final e in o.wants.entries)
        if (game.count(e.key) < e.value) e.key,
    ];
    return _Card(
      icon: HatarakiItemIcon(o.wants.keys.first, size: 44),
      title: o.big ? l.hatarakiOrderBig : l.hatarakiOrder,
      subtitle: o.done
          ? l.hatarakiOrderDone
          : o.big
          ? l.hatarakiOrderBigHint
          : l.hatarakiOrderHint,
      children: [
        _Label(l.hatarakiOrderWants),
        _ItemRow(items: o.wants, have: game, counts: true),
        if (missing.contains(hParcel))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l.hatarakiParcelHint, style: Ty.micro),
          ),
        if (!o.done) _Sources(items: missing.where((id) => id != hParcel)),
        _Label(l.hatarakiOrderPays),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ResultChip(
              text: '${o.money}',
              icon: const ArtIconView(ArtIcon.ginmon, size: 16),
            ),
            if (o.skill != null && o.xp > 0)
              ResultChip(
                text: l.hatarakiOrderXp(o.xp, hSkillName(l, o.skill!)),
                icon: HatarakiSkillIcon(o.skill!, size: 16),
              ),
            if (o.gift != null)
              ResultChip(
                text: '${hItemName(l, o.gift!)} ×${o.giftN}',
                icon: HatarakiItemIcon(o.gift!, size: 16),
              ),
            if (o.big)
              ResultChip(
                text: l.hatarakiOrderTicket,
                icon: const ArtIconView(ArtIcon.ticketGachaken, size: 16),
              ),
          ],
        ),
        if (o.big && ticketToday && !o.done)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l.hatarakiOrderTicketUsed,
              style: Ty.micro.copyWith(color: T.warn),
            ),
          ),
      ],
    );
  }
}
