// Ibasho — canal del buzon de sugerencias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/suggestions.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';
import '../../layout.dart';
import '../channel_route.dart';

/// El buzon: una sugerencia viva por cuenta, la lista publica de las que se
/// aceptaron y, para quien manda, la cola de veredictos pendientes.
class SuggestionsChannel extends ConsumerStatefulWidget {
  const SuggestionsChannel({super.key});

  @override
  ConsumerState<SuggestionsChannel> createState() => _SuggestionsChannelState();
}

class _SuggestionsChannelState extends ConsumerState<SuggestionsChannel> {
  final TextEditingController _headline = TextEditingController();
  final TextEditingController _body = TextEditingController();

  bool _sending = false;

  /// Con un veredicto ya en pantalla el formulario no vuelve solo: se abre al
  /// pulsar "mandar otra", para que la respuesta no desaparezca de golpe.
  bool _composing = false;

  String? _headlineError;
  String? _bodyError;

  @override
  void dispose() {
    _headline.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = L.of(context)!;
    final headline = _headline.text.trim();
    final body = _body.text.trim();
    if (headline.isEmpty || body.isEmpty) {
      AudioService.instance.play(Sfx.error);
      // El aviso va en el campo que falta: el texto es el mismo para los dos,
      // asi que marcarlos ambos solo repetiria la misma linea.
      setState(() {
        _headlineError = headline.isEmpty ? l.suggestErrorEmpty : null;
        _bodyError = headline.isEmpty ? null : l.suggestErrorEmpty;
      });
      return;
    }

    setState(() {
      _headlineError = null;
      _bodyError = null;
      _sending = true;
    });
    final sent = await ref
        .read(suggestionsProvider.notifier)
        .submit(title: headline, body: body);
    if (!mounted) return;
    AudioService.instance.play(sent ? Sfx.open : Sfx.error);
    setState(() {
      _sending = false;
      if (sent) {
        _headline.clear();
        _body.clear();
        _composing = false;
      }
    });
    if (!sent) showIbashoToast(context, l.suggestError, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final state = ref.watch(suggestionsProvider);
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));

    // El formulario solo aparece cuando de verdad se puede mandar algo: con
    // una esperando respuesta se ve el sello y nada mas, y con un veredicto ya
    // dado hace falta pedirlo.
    final composing = state.canSubmit && (state.mine == null || _composing);

    return ChannelScaffold(
      title: l.suggestTitle,
      glyph: Glyph.bulb,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(28, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(880, layout.column),
            child: !state.loaded
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: Text(l.loading, style: Ty.caption)),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.mine != null) ...[
                        _MineCard(suggestion: state.mine!),
                        const SizedBox(height: 22),
                      ],
                      if (!state.open)
                        SectionCard(
                          child: Row(
                            children: [
                              GlyphIcon(Glyph.lock, size: 22, color: Ty.inkSoft),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(l.suggestClosed, style: Ty.body),
                              ),
                            ],
                          ),
                        )
                      else if (composing)
                        _Compose(
                          headline: _headline,
                          body: _body,
                          headlineError: _headlineError,
                          bodyError: _bodyError,
                          sending: _sending,
                          onSend: _send,
                        )
                      else if (state.mine != null)
                        // Hay veredicto: la respuesta ya se ve arriba y solo
                        // falta la puerta para abrir el formulario otra vez.
                        Align(
                          alignment: layout.pick(Alignment.centerLeft, Alignment.center),
                          child: IbashoButton(
                            label: l.suggestAnother,
                            glyph: Glyph.plus,
                            expand: layout.tall,
                            onPressed: () => setState(() => _composing = true),
                          ),
                        ),
                      const SizedBox(height: 22),
                      _AcceptedList(accepted: state.accepted),
                      if (isAdmin) ...[
                        const SizedBox(height: 22),
                        _AdminSection(pending: state.pending, open: state.open),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// La sugerencia propia con su sello. Es lo primero que se busca al entrar.
class _MineCard extends StatelessWidget {
  const _MineCard({required this.suggestion});

  final Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;

    return SectionCard(
      title: l.suggestYours,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(suggestion.title, style: Ty.lead)),
              const SizedBox(width: 16),
              _StatusSeal(status: suggestion.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(suggestion.body, style: Ty.body.copyWith(color: Ty.inkSoft)),
          if (suggestion.note != null) ...[
            const SizedBox(height: 16),
            GlossSurface(
              radius: 16,
              recessed: true,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.note!, style: Ty.body),
                  if (suggestion.decidedBy != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        l.suggestDecidedBy(suggestion.decidedBy!),
                        style: Ty.caption,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// El sello del veredicto: el acento se reserva para la aceptada, la rechazada
/// se apaga y la que espera se queda en plastico sin tenir.
class _StatusSeal extends StatelessWidget {
  const _StatusSeal({required this.status});

  final SuggestionStatus status;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final (label, glyph) = switch (status) {
      SuggestionStatus.accepted => (l.suggestStatusAccepted, Glyph.check),
      SuggestionStatus.rejected => (l.suggestStatusRejected, Glyph.cross),
      SuggestionStatus.pending => (l.suggestStatusPending, Glyph.clock),
    };
    final accepted = status == SuggestionStatus.accepted;
    final rejected = status == SuggestionStatus.rejected;
    final ink = accepted ? T.onAccent : Ty.inkSoft;

    return GlossSurface(
      radius: 13,
      tint: accepted ? skin.accent : null,
      recessed: rejected,
      elevation: accepted ? 1 : .5,
      borderColor: accepted ? skin.accentDeep : skin.hairline,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(glyph, size: 15, color: ink),
          const SizedBox(width: 7),
          Text(
            label,
            style: Ty.micro.copyWith(
              color: accepted ? T.onAccent : Ty.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// El formulario de una sugerencia nueva.
class _Compose extends StatelessWidget {
  const _Compose({
    required this.headline,
    required this.body,
    required this.headlineError,
    required this.bodyError,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController headline;
  final TextEditingController body;
  final String? headlineError;
  final String? bodyError;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.suggestIntro, style: Ty.body.copyWith(color: Ty.inkSoft)),
          const SizedBox(height: 18),
          _Counted(
            controller: headline,
            maximum: suggestionTitleMax,
            field: IbashoTextField(
              controller: headline,
              label: l.suggestHeadline,
              maxLength: suggestionTitleMax,
              error: headlineError,
            ),
          ),
          _Counted(
            controller: body,
            maximum: suggestionBodyMax,
            field: IbashoTextField(
              controller: body,
              label: l.suggestBody,
              maxLength: suggestionBodyMax,
              multiline: true,
              error: bodyError,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: tall ? Alignment.center : Alignment.centerRight,
            child: IbashoButton(
              label: sending ? l.suggestSending : l.suggestSend,
              glyph: Glyph.send,
              tone: ButtonTone.accent,
              expand: tall,
              // El sonido lo pone el envio: abierto si sale, error si no.
              cue: null,
              onPressed: sending ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

/// Un campo con su contador de caracteres.
///
/// El contador se cuela en la linea de la etiqueta, que ya esta ahi y sobra
/// ancho a la derecha: asi se ve cuanto queda sin meter otra fila entre el
/// campo y el hueco que el propio campo reserva para su error.
class _Counted extends StatelessWidget {
  const _Counted({
    required this.controller,
    required this.maximum,
    required this.field,
  });

  final TextEditingController controller;
  final int maximum;
  final Widget field;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          field,
          Positioned(
            top: 0,
            right: 6,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => Text(
                '${value.text.characters.length}/$maximum',
                style: Ty.numeral(12, color: Ty.inkSoft),
              ),
            ),
          ),
        ],
      );
}

/// Las aceptadas, a la vista de todos. Es la prueba de que el buzon sirve de
/// algo, asi que se ve aunque nunca hayas mandado nada.
class _AcceptedList extends StatelessWidget {
  const _AcceptedList({required this.accepted});

  final List<AcceptedSuggestion> accepted;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    return SectionCard(
      title: l.suggestAcceptedList,
      padding: const EdgeInsets.fromLTRB(26, 6, 26, 10),
      child: accepted.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text(l.suggestAcceptedEmpty, style: Ty.caption)),
            )
          : Column(
              children: [
                for (var i = 0; i < accepted.length; i++) ...[
                  if (i > 0) const Hairline(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: GlossSurface(
                            radius: 11,
                            tint: skin.accent,
                            borderColor: skin.accentDeep,
                            child: const Center(
                              child: GlyphIcon(Glyph.check, size: 17, color: T.onAccent),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(accepted[i].title, style: Ty.body),
                              const SizedBox(height: 2),
                              Text(accepted[i].by, style: Ty.micro),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

/// La cola de veredictos y la llave del buzon. Solo la ve quien manda: si no
/// es admin, `pending` ni siquiera se llena.
class _AdminSection extends ConsumerStatefulWidget {
  const _AdminSection({required this.pending, required this.open});

  final List<Suggestion> pending;
  final bool open;

  @override
  ConsumerState<_AdminSection> createState() => _AdminSectionState();
}

class _AdminSectionState extends ConsumerState<_AdminSection> {
  bool _switching = false;

  Future<void> _setOpen(bool open) async {
    final l = L.of(context)!;
    setState(() => _switching = true);
    final done = await ref.read(suggestionsProvider.notifier).setOpen(open);
    if (!mounted) return;
    AudioService.instance.play(done ? Sfx.open : Sfx.error);
    setState(() => _switching = false);
    if (!done) showIbashoToast(context, l.adminSuggestError, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;

    return SectionCard(
      title: l.adminSuggestSection,
      padding: const EdgeInsets.fromLTRB(26, 6, 26, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            label: l.adminSuggestBox,
            hint: widget.open ? l.adminSuggestBoxOpen : l.adminSuggestBoxClosed,
            control: IbashoToggle(
              value: widget.open,
              onChanged: _switching ? null : _setOpen,
            ),
          ),
          if (widget.pending.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text(l.adminSuggestEmpty, style: Ty.caption)),
            )
          else
            for (var i = 0; i < widget.pending.length; i++) ...[
              if (i > 0) const Hairline(),
              _PendingRow(
                key: ValueKey<String>('suggest.pending.${widget.pending[i].accountId}'),
                suggestion: widget.pending[i],
              ),
            ],
        ],
      ),
    );
  }
}

/// Una sugerencia esperando veredicto, con su motivo y sus dos salidas.
class _PendingRow extends ConsumerStatefulWidget {
  const _PendingRow({super.key, required this.suggestion});

  final Suggestion suggestion;

  @override
  ConsumerState<_PendingRow> createState() => _PendingRowState();
}

class _PendingRowState extends ConsumerState<_PendingRow> {
  final TextEditingController _note = TextEditingController();

  bool _working = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _decide(bool accept, String authorName) async {
    final l = L.of(context)!;
    final decidedBy = ref.read(profileProvider).profile?.displayName ?? '';
    setState(() => _working = true);
    final done = await ref.read(suggestionsProvider.notifier).decide(
          suggestion: widget.suggestion,
          accept: accept,
          note: _note.text.trim(),
          decidedBy: decidedBy,
          // Lo que se publica en la lista es el nombre, no la cuenta: la
          // aceptada se lee sin tener que resolver nada despues.
          authorName: authorName,
        );
    if (!mounted) return;
    AudioService.instance.play(done ? Sfx.open : Sfx.error);
    setState(() => _working = false);
    if (!done) showIbashoToast(context, l.adminSuggestError, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tall = Layout.of(context).tall;
    final card = ref.watch(cardOfProvider(widget.suggestion.accountId)).valueOrNull;
    // Sin ficha no hay nombre que ensenar: la cuenta no ha estrenado la suya.
    final author = card?.displayName ?? l.addFriendNoCard;

    final buttons = [
      IbashoButton(
        label: l.adminSuggestAccept,
        glyph: Glyph.check,
        tone: ButtonTone.accent,
        height: 42,
        expand: tall,
        cue: null,
        onPressed: _working ? null : () => _decide(true, author),
      ),
      IbashoButton(
        label: l.adminSuggestReject,
        glyph: Glyph.cross,
        height: 42,
        expand: tall,
        cue: null,
        onPressed: _working ? null : () => _decide(false, author),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.suggestion.title, style: Ty.body),
          const SizedBox(height: 4),
          Text(widget.suggestion.body, style: Ty.caption),
          const SizedBox(height: 6),
          Row(
            children: [
              GlyphIcon(Glyph.person, size: 15, color: Ty.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.micro),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _Counted(
            controller: _note,
            maximum: suggestionNoteMax,
            field: IbashoTextField(
              controller: _note,
              label: l.adminSuggestNote,
              maxLength: suggestionNoteMax,
              enabled: !_working,
            ),
          ),
          // En vertical los dos veredictos se reparten la linea entera; en
          // horizontal se quedan a la derecha, donde acaba la lectura.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (tall) ...[
                Expanded(child: buttons[1]),
                const SizedBox(width: 12),
                Expanded(child: buttons[0]),
              ] else ...[
                buttons[1],
                const SizedBox(width: 12),
                buttons[0],
              ],
            ],
          ),
        ],
      ),
    );
  }
}
