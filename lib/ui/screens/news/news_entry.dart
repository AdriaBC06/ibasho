// Ibasho — una entrada del tablon de noticias, con su encuesta si la trae.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/news.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';

/// Una entrada del tablon: la etiqueta de que es, el texto y, si es una
/// encuesta, el recuento en vivo con sus barras.
///
/// El voto se manda desde aqui porque la entrada es quien sabe si sigue
/// abierta: la hora sale del reloj compartido, asi que una encuesta con fecha
/// de cierre se apaga sola mientras el canal esta delante, sin recargar nada.
class NewsEntry extends ConsumerWidget {
  const NewsEntry({super.key, required this.item, required this.isAdmin});

  final NewsItem item;
  final bool isAdmin;

  Future<void> _vote(BuildContext context, WidgetRef ref, int option) async {
    final l = L.of(context)!;
    // Repetir el voto que ya tienes no escribe nada: solo un tick de que se
    // ha oido la pulsacion.
    if (ref.read(newsProvider).voteOn(item.id) == option) {
      AudioService.instance.play(Sfx.tick);
      return;
    }
    final done = await ref.read(newsProvider.notifier).vote(item.id, option);
    if (!context.mounted) return;
    if (done) {
      AudioService.instance.play(Sfx.open);
      return;
    }
    AudioService.instance.play(Sfx.error);
    showIbashoToast(context, l.pollError, isError: true);
  }

  Future<void> _closePoll(BuildContext context, WidgetRef ref) async {
    final l = L.of(context)!;
    final done = await ref.read(newsProvider.notifier).closePoll(item.id);
    if (!context.mounted) return;
    AudioService.instance.play(done ? Sfx.open : Sfx.error);
    if (!done) showIbashoToast(context, l.adminNewsError, isError: true);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l = L.of(context)!;
    final confirmed = await askConfirmation(
      context,
      title: l.adminNewsDelete,
      body: l.adminNewsDeleteConfirm,
      confirmLabel: l.adminNewsDelete,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!confirmed || !context.mounted) return;
    final done = await ref.read(newsProvider.notifier).remove(item.id);
    if (!context.mounted) return;
    AudioService.instance.play(done ? Sfx.open : Sfx.error);
    if (!done) showIbashoToast(context, l.adminNewsError, isError: true);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final date = DateFormat.yMMMd(locale);

    // Del reloj solo importa el instante en que la encuesta se cierra sola:
    // con `select` la entrada no se rehace con cada latido de segundo, solo
    // cuando la respuesta cambia de si a no.
    final open = ref.watch(clockProvider.select(item.isOpenAt));
    final myVote = ref.watch(newsProvider.select((n) => n.voteOn(item.id)));

    return SectionCard(
      padding: Layout.of(context).pick(
        const EdgeInsets.fromLTRB(26, 22, 26, 22),
        const EdgeInsets.fromLTRB(20, 18, 20, 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Etiqueta y version comparten linea, pero en vertical bajan sin
          // recortarse: los dos son piezas de ancho propio.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _KindChip(kind: item.kind),
              if (item.version != null)
                Text(
                  l.newsVersionTag(item.version!),
                  style: Ty.caption.copyWith(color: skin.accentDeep),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(item.titleIn(locale), style: Ty.lead),
          if (item.bodyIn(locale).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.bodyIn(locale), style: Ty.body.copyWith(color: T.inkSoft)),
          ],
          if (item.isPoll) ...[
            const SizedBox(height: 18),
            _Poll(
              item: item,
              open: open,
              myVote: myVote,
              closesLabel: !open
                  ? l.pollClosed
                  : item.closesAt == null
                      ? l.pollNoClose
                      : l.pollClosesOn(date.format(item.closesAt!)),
              onVote: (option) => _vote(context, ref, option),
            ),
          ],
          const SizedBox(height: 16),
          const Hairline(),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(date.format(item.at), style: Ty.micro),
              if (item.by.isNotEmpty) Text(l.newsBy(item.by), style: Ty.micro),
            ],
          ),
          if (isAdmin) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (item.isPoll && open)
                  IbashoButton(
                    label: l.adminNewsClosePoll,
                    tone: ButtonTone.quiet,
                    height: 40,
                    cue: null,
                    onPressed: () => _closePoll(context, ref),
                  ),
                IbashoButton(
                  label: l.adminNewsDelete,
                  glyph: Glyph.trash,
                  tone: ButtonTone.quiet,
                  height: 40,
                  cue: null,
                  onPressed: () => _remove(context, ref),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// La chapa de que clase de entrada es.
///
/// La novedad se lleva el acento porque es lo que se viene a buscar; el aviso
/// va en tinta suave, que no compite con nada; la encuesta usa el acento
/// oscurecido para distinguirse de la novedad sin meter un segundo color en
/// un entorno que solo tiene uno.
class _KindChip extends StatelessWidget {
  const _KindChip({required this.kind});

  final NewsKind kind;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final (label, tint) = switch (kind) {
      NewsKind.update => (l.newsKindUpdate, skin.accent),
      NewsKind.note => (l.newsKindNote, T.inkSoft),
      NewsKind.poll => (l.newsKindPoll, skin.accentDeep),
    };

    return GlossSurface(
      radius: 10,
      tint: tint,
      elevation: .5,
      borderColor: Color.lerp(tint, T.dusk, .34)!,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: Ty.micro.copyWith(color: T.onAccent, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// El cuerpo de una encuesta: las opciones con su barra y el pie con el
/// recuento, el cierre y la promesa de anonimato.
class _Poll extends StatelessWidget {
  const _Poll({
    required this.item,
    required this.open,
    required this.myVote,
    required this.closesLabel,
    required this.onVote,
  });

  final NewsItem item;
  final bool open;
  final int? myVote;
  final String closesLabel;
  final ValueChanged<int> onVote;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final opciones = item.optionsIn(Localizations.localeOf(context).languageCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < opciones.length; i++)
          _PollOption(
            label: opciones[i],
            share: item.share(i),
            mine: myVote == i,
            open: open,
            onPressed: () => onVote(i),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text(
              l.pollVotes(item.totalVotes),
              style: Ty.caption.copyWith(color: T.ink),
            ),
            Text(closesLabel, style: Ty.caption),
            if (open && myVote != null) Text(l.pollChangeHint, style: Ty.caption),
          ],
        ),
        const SizedBox(height: 8),
        // El anonimato no es una nota al pie: es lo que hace que la gente
        // vote de verdad, asi que se lee siempre, con voto o sin el.
        Row(
          children: [
            const GlyphIcon(Glyph.lock, size: 15, color: T.inkSoft),
            const SizedBox(width: 8),
            Expanded(child: Text(l.pollAnonymous, style: Ty.micro)),
          ],
        ),
      ],
    );
  }
}

/// Una opcion: el texto arriba, la barra debajo.
///
/// El porcentaje va en numero aparte y la barra se mueve sola cuando cambia el
/// recuento, que llega por el stream mientras la pantalla esta abierta.
class _PollOption extends StatelessWidget {
  const _PollOption({
    required this.label,
    required this.share,
    required this.mine,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final double share;
  final bool mine;
  final bool open;
  final VoidCallback onPressed;

  static const double _barHeight = 12;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    return Pressable(
      // El sonido lo pone el voto: hasta que no entra en el servidor no hay
      // nada que celebrar.
      cue: null,
      onPressed: open ? onPressed : null,
      cursor: open ? SystemMouseCursors.click : SystemMouseCursors.basic,
      semanticLabel: label,
      builder: (context, state) {
        final fill = mine
            ? skin.accent
            : Color.lerp(skin.accent, T.shellBottom, .55 - .2 * state.hover)!;
        final ink = mine ? skin.accentDeep : T.ink;

        return FocusRing(
          visible: state.focus,
          radius: 12,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (mine) ...[
                      GlyphIcon(Glyph.check, size: 16, color: skin.accentDeep),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.body.copyWith(
                          color: ink,
                          fontWeight: mine ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (mine)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          l.pollYourVote,
                          style: Ty.micro.copyWith(color: skin.accentDeep),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Text(
                      '${(share * 100).round()}%',
                      style: Ty.numeral(15, color: mine ? skin.accentDeep : T.inkSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                SizedBox(
                  height: _barHeight,
                  child: GlossSurface(
                    radius: _barHeight / 2,
                    recessed: true,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: share.clamp(0.0, 1.0)),
                      duration: skin.motion(const Duration(milliseconds: 420)),
                      curve: skin.curve(Curves.easeOutCubic),
                      builder: (context, value, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: value,
                          heightFactor: 1,
                          child: GlossSurface(
                            radius: _barHeight / 2,
                            tint: fill,
                            elevation: 0,
                            specular: .8,
                            borderColor: Color.lerp(fill, T.dusk, .3)!,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
