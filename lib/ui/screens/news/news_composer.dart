// Ibasho — el formulario con el que el admin publica en el tablon.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/news.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';

/// Publicar en el tablon, dentro del propio canal.
///
/// No hay pantalla aparte: el admin escribe justo encima de lo que va a leer
/// todo el mundo, y asi ve al momento como queda la entrada publicada.
class NewsComposer extends ConsumerStatefulWidget {
  const NewsComposer({super.key});

  @override
  ConsumerState<NewsComposer> createState() => _NewsComposerState();
}

class _NewsComposerState extends ConsumerState<NewsComposer> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _version = TextEditingController();
  final List<TextEditingController> _options = [
    for (var i = 0; i < pollOptionsMin; i++) TextEditingController(),
  ];

  NewsKind _kind = NewsKind.update;

  /// Dias hasta el cierre. 0 es la encuesta que se cierra a mano.
  int _closeAfter = 0;

  bool _busy = false;
  String? _titleError;
  String? _optionsError;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _version.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _setKind(NewsKind kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _optionsError = null;
    });
  }

  void _addOption() {
    if (_options.length >= pollOptionsMax) return;
    setState(() {
      _options.add(TextEditingController());
      _optionsError = null;
    });
  }

  void _removeOption(int index) {
    if (_options.length <= pollOptionsMin) return;
    setState(() {
      _options.removeAt(index).dispose();
      _optionsError = null;
    });
  }

  void _clear() {
    _title.clear();
    _body.clear();
    _version.clear();
    for (final option in _options) {
      option.clear();
    }
    setState(() {
      _closeAfter = 0;
      _titleError = null;
      _optionsError = null;
    });
  }

  Future<void> _publish() async {
    final l = L.of(context)!;
    final title = _title.text.trim();
    final poll = _kind == NewsKind.poll;
    final options = [
      for (final option in _options)
        if (option.text.trim().isNotEmpty) option.text.trim(),
    ];

    if (title.isEmpty) {
      AudioService.instance.play(Sfx.error);
      setState(() {
        _titleError = l.adminNewsErrorEmpty;
        _optionsError = null;
      });
      return;
    }
    if (poll && options.length < pollOptionsMin) {
      AudioService.instance.play(Sfx.error);
      setState(() {
        _titleError = null;
        _optionsError = l.adminNewsErrorOptions;
      });
      return;
    }

    // Quien firma es la persona, no la cuenta: el nombre visible del perfil y,
    // mientras no lo tenga puesto, el usuario con el que entra.
    final displayName = ref.read(profileProvider).profile?.displayName ?? '';
    final by = displayName.isNotEmpty
        ? displayName
        : ref.read(sessionProvider).username;
    final version = _version.text.trim();

    setState(() {
      _busy = true;
      _titleError = null;
      _optionsError = null;
    });
    final id = await ref.read(newsProvider.notifier).publish(
          kind: _kind,
          title: title,
          body: _body.text.trim(),
          version: _kind == NewsKind.update && version.isNotEmpty ? version : null,
          options: poll ? options : const <String>[],
          closesAt: poll && _closeAfter > 0
              ? DateTime.now().add(Duration(days: _closeAfter))
              : null,
          by: by,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id == null) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.adminNewsError, isError: true);
      return;
    }
    AudioService.instance.play(Sfx.open);
    showIbashoToast(context, l.adminNewsPublished);
    _clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final poll = _kind == NewsKind.poll;

    return SectionCard(
      title: l.adminNewsSection,
      padding: layout.pick(
        const EdgeInsets.fromLTRB(26, 10, 26, 22),
        const EdgeInsets.fromLTRB(20, 8, 20, 18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingRow(
            label: l.adminNewsKind,
            control: IbashoSegmented<NewsKind>(
              options: [
                (NewsKind.update, l.newsKindUpdate),
                (NewsKind.note, l.newsKindNote),
                (NewsKind.poll, l.newsKindPoll),
              ],
              value: _kind,
              onChanged: _setKind,
            ),
          ),
          const SizedBox(height: 16),
          IbashoTextField(
            controller: _title,
            label: l.adminNewsHeadline,
            maxLength: newsTitleMax,
            error: _titleError,
            enabled: !_busy,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          IbashoTextField(
            controller: _body,
            label: l.adminNewsBody,
            maxLength: newsBodyMax,
            multiline: true,
            enabled: !_busy,
          ),
          // La version solo tiene sentido en una novedad: es la que se anuncia.
          if (_kind == NewsKind.update)
            IbashoTextField(
              controller: _version,
              label: l.adminNewsVersion,
              maxLength: 16,
              enabled: !_busy,
            ),
          if (poll) ...[
            for (var i = 0; i < _options.length; i++)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: IbashoTextField(
                      controller: _options[i],
                      label: l.adminNewsOption(i + 1),
                      maxLength: pollOptionMax,
                      enabled: !_busy,
                    ),
                  ),
                  // El boton se baja el alto de la etiqueta del campo para
                  // quedar a la altura del hueco, no de su titulo.
                  if (_options.length > pollOptionsMin)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 26),
                      child: IbashoButton(
                        label: l.adminNewsRemoveOption,
                        tone: ButtonTone.quiet,
                        height: 42,
                        onPressed: _busy ? null : () => _removeOption(i),
                      ),
                    ),
                ],
              ),
            if (_optionsError != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 10),
                child: Text(
                  _optionsError!,
                  style: Ty.caption.copyWith(color: T.warn),
                ),
              ),
            if (_options.length < pollOptionsMax)
              Align(
                alignment: Alignment.centerLeft,
                child: IbashoButton(
                  label: l.adminNewsAddOption,
                  glyph: Glyph.plus,
                  height: 42,
                  onPressed: _busy ? null : _addOption,
                ),
              ),
            SettingRow(
              label: l.adminNewsCloseAfter,
              divider: false,
              control: IbashoSegmented<int>(
                options: [
                  (0, l.adminNewsNoDeadline),
                  (1, l.adminNewsDays(1)),
                  (3, l.adminNewsDays(3)),
                  (7, l.adminNewsDays(7)),
                ],
                value: _closeAfter,
                onChanged: (days) => setState(() => _closeAfter = days),
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: layout.pick(Alignment.centerRight, Alignment.center),
            child: IbashoButton(
              label: l.adminNewsPublish,
              glyph: Glyph.send,
              tone: ButtonTone.accent,
              expand: layout.tall,
              minWidth: layout.pick(160, 0),
              // El sonido lo pone la respuesta del servidor, no la pulsacion.
              cue: null,
              onPressed: _busy ? null : _publish,
            ),
          ),
        ],
      ),
    );
  }
}
