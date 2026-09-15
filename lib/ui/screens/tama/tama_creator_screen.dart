// Ibasho — el creador de Tamas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/tama.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../state/tamas.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../tama/accent_prompt.dart';
import '../../tama/tama_text.dart';
import '../../tama/tama_view.dart';
import '../../tama/tama_widgets.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../../widgets/text_field.dart';
import '../channel_route.dart';
import 'tama_room_screen.dart';

/// Pestañas del creador.
enum CreatorTab { body, color, eyes, mouth, crown, cheeks, limbs, character }

/// Lo que se edita: todo lo que el creador de un Tama puede cambiar.
class _Draft {
  const _Draft({
    required this.look,
    required this.name,
    required this.personality,
    required this.voice,
  });

  final TamaLook look;
  final String name;
  final TamaPersonality personality;
  final TamaVoice voice;

  _Draft copyWith({
    TamaLook? look,
    String? name,
    TamaPersonality? personality,
    TamaVoice? voice,
  }) =>
      _Draft(
        look: look ?? this.look,
        name: name ?? this.name,
        personality: personality ?? this.personality,
        voice: voice ?? this.voice,
      );

  bool sameAs(_Draft other) =>
      look == other.look &&
      name.trim() == other.name.trim() &&
      personality == other.personality &&
      voice == other.voice;
}

/// Crea un Tama nuevo (sin `tamaId`) o edita uno existente.
class TamaCreatorScreen extends ConsumerStatefulWidget {
  const TamaCreatorScreen({super.key, this.tamaId, this.initialTab = CreatorTab.body});

  final String? tamaId;
  final CreatorTab initialTab;

  @override
  ConsumerState<TamaCreatorScreen> createState() => _TamaCreatorScreenState();
}

class _TamaCreatorScreenState extends ConsumerState<TamaCreatorScreen> {
  final math.Random _rng = math.Random();
  final TamaViewController _view = TamaViewController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _hex = TextEditingController();
  final List<_Draft> _undo = <_Draft>[];

  late _Draft _draft;
  late _Draft _saved;
  late CreatorTab _tab = widget.initialTab;
  bool _seeded = false;
  bool _saving = false;
  String? _nameError;
  String? _hexError;

  bool get _isNew => widget.tamaId == null;

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    super.dispose();
  }

  void _seed(Tama? existing) {
    if (existing != null) {
      _draft = _Draft(
        look: existing.look,
        name: existing.name,
        personality: existing.personality,
        voice: existing.voice,
      );
    } else {
      // Un Tama nuevo empieza ya bonito: al azar, pero de la paleta.
      _draft = _Draft(
        look: TamaLook.random(_rng),
        name: '',
        personality: TamaPersonality.values[_rng.nextInt(TamaPersonality.values.length)],
        voice: TamaVoice(pitch: 35 + _rng.nextInt(40), tempo: 35 + _rng.nextInt(40)),
      );
    }
    _saved = _draft;
    _name.text = _draft.name;
    _hex.text = _draft.look.color;
    _seeded = true;
  }

  // --- Edicion ---------------------------------------------------------------

  /// Apunta el estado actual en la pila de deshacer.
  void _checkpoint() {
    if (_undo.isNotEmpty && _undo.last.sameAs(_draft)) return;
    _undo.add(_draft);
    if (_undo.length > 60) _undo.removeAt(0);
  }

  void _apply(_Draft next, {bool checkpoint = true}) {
    if (checkpoint) _checkpoint();
    setState(() {
      _draft = next;
      if (_hex.text.toUpperCase() != next.look.color) _hex.text = next.look.color;
      _hexError = null;
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    AudioService.instance.play(Sfx.back);
    final previous = _undo.removeLast();
    setState(() {
      _draft = previous;
      _name.text = previous.name;
      _hex.text = previous.look.color;
    });
  }

  void _shuffle() {
    AudioService.instance.play(Sfx.tick);
    _apply(_draft.copyWith(look: TamaLook.random(_rng)));
    _view.speak();
  }

  bool get _dirty => !_draft.sameAs(_saved);

  Future<void> _close() async {
    if (_dirty) {
      final l = L.of(context)!;
      final leave = await askConfirmation(
        context,
        title: l.tamaCreatorDiscardTitle,
        body: l.tamaCreatorDiscardBody,
        confirmLabel: l.tamaCreatorDiscard,
        cancelLabel: l.tamaCreatorKeepEditing,
        tone: ButtonTone.warn,
      );
      if (!leave || !mounted) return;
    }
    AudioService.instance.play(Sfx.back);
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    final l = L.of(context)!;
    final name = _name.text.trim();
    if (name.isEmpty || name.length > tamaNameMax) {
      AudioService.instance.play(Sfx.error);
      setState(() {
        _nameError = l.tamaNameError;
        _tab = CreatorTab.character;
      });
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    final controller = ref.read(tamasProvider.notifier);
    final draft = _draft.copyWith(name: name);

    if (_isNew) {
      final (id, failure) = await controller.create(
        name: draft.name,
        personality: draft.personality,
        voice: draft.voice,
        look: draft.look,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (id == null) {
        AudioService.instance.play(Sfx.error);
        showIbashoToast(
          context,
          switch (failure) {
            TamaCreateFailure.full => l.tamasFull(maxTamasPerAccount),
            TamaCreateFailure.network => l.tamaCreateNetwork,
            _ => l.tamaCreateError,
          },
          isError: true,
        );
        return;
      }
      _saved = draft;
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, l.tamaCreated(draft.name));
      final navigator = Navigator.of(context);
      final reduced = IbashoSkin.of(context).reducedMotion;
      if (ref.read(tamasProvider).profileTamaId == id) {
        await reconcileAccentWithTama(context, ref, draft.look.color);
      }
      if (!mounted) return;
      // Al crear se pasa directamente a su habitacion.
      unawaited(navigator.pushReplacement(
        ChannelPageRoute<void>(
          builder: (_) => TamaRoomScreen(tamaId: id),
          reducedMotion: reduced,
        ),
      ));
      return;
    }

    final existing = ref.read(tamasProvider).byId(widget.tamaId);
    if (existing == null) return;
    final ok = await controller.saveIdentity(existing.copyWith(
      name: draft.name,
      personality: draft.personality,
      voice: draft.voice,
      look: draft.look,
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.tamaSaveError, isError: true);
      return;
    }
    final colorChanged = existing.look.color != draft.look.color;
    _saved = draft;
    AudioService.instance.play(Sfx.open);
    showIbashoToast(context, l.tamaSaved(draft.name));
    if (colorChanged && ref.read(tamasProvider).profileTamaId == existing.id) {
      await reconcileAccentWithTama(context, ref, draft.look.color);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // --- Pintado ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final tamas = ref.watch(tamasProvider);
    final existing = _isNew ? null : tamas.byId(widget.tamaId);
    final account = ref.watch(sessionProvider.select((s) => s.accountId));

    if (!_seeded) {
      if (!_isNew && existing == null) {
        return ChannelScaffold(
          title: l.channelTamas,
          glyph: Glyph.tama,
          child: Center(child: Text(l.loading, style: Ty.lead)),
        );
      }
      _seed(existing);
    }

    final canEdit = _isNew || (existing?.createdBy(account) ?? false);
    final preview = Tama(
      id: widget.tamaId ?? 'borrador',
      creator: account,
      keeper: account,
      name: _name.text.trim().isEmpty ? l.tamaCreatorNewTitle : _name.text.trim(),
      personality: _draft.personality,
      voice: _draft.voice,
      look: _draft.look,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    return ChannelScaffold(
      title: _isNew ? l.tamaCreatorNewTitle : l.tamaCreatorEditTitle(existing!.name),
      glyph: Glyph.tama,
      onClose: _close,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Escenario: el Tama vivo, con barajar y deshacer debajo.
          SizedBox(
            width: 460,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TamaOnStand(
                  key: const ValueKey<String>('creator.stage'),
                  tama: preview,
                  size: 330,
                  controller: _view,
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IbashoButton(
                      key: const ValueKey<String>('creator.shuffle'),
                      label: l.tamaCreatorShuffle,
                      glyph: Glyph.dice,
                      height: 46,
                      cue: null,
                      onPressed: canEdit ? _shuffle : null,
                    ),
                    const SizedBox(width: 12),
                    IbashoButton(
                      key: const ValueKey<String>('creator.undo'),
                      label: l.tamaCreatorUndo,
                      glyph: Glyph.undo,
                      height: 46,
                      cue: null,
                      onPressed: _undo.isEmpty ? null : _undoLast,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 22, 40, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TabRail(
                    value: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                  const SizedBox(height: 16),
                  // La misma tarjeta que SectionCard, pero ocupando todo el
                  // alto: el contenido de cada pestaña se desplaza dentro.
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [T.onAccent, T.cardBottom],
                        ),
                        border: Border.all(color: T.hairline),
                        boxShadow: const [
                          BoxShadow(color: T.shadow, blurRadius: 10, offset: Offset(0, 3)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: IgnorePointer(
                          ignoring: !canEdit,
                          child: Opacity(
                            opacity: canEdit ? 1 : .55,
                            child: SizedBox.expand(
                              child: IbashoScroll(
                                key: ValueKey<CreatorTab>(_tab),
                                padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                                child: _tabContent(l),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (!canEdit)
                        Expanded(child: Text(l.tamaCreatorNotCreator, style: Ty.caption))
                      else
                        const Spacer(),
                      IbashoButton(
                        label: l.actionCancel,
                        tone: ButtonTone.quiet,
                        cue: null,
                        onPressed: _close,
                      ),
                      const SizedBox(width: 12),
                      IbashoButton(
                        key: const ValueKey<String>('creator.save'),
                        label: _saving
                            ? l.changePasswordWorking
                            : (_isNew ? l.tamaCreatorCreate : l.actionSave),
                        glyph: Glyph.check,
                        tone: ButtonTone.accent,
                        height: 50,
                        minWidth: 180,
                        cue: null,
                        onPressed: !canEdit || _saving || (!_isNew && !_dirty) ? null : _save,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabContent(L l) {
    final look = _draft.look;

    Widget parts(TamaPart part, {double zoom = 1, Alignment focus = Alignment.center}) =>
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (var v = 0; v < part.variants; v++)
              TamaStyleChip(
                key: ValueKey<String>('creator.${part.name}.$v'),
                look: look.withPart(part, v),
                label: variantLabel(l, part, v),
                selected: look.part(part) == v,
                zoom: zoom,
                focus: focus,
                onPressed: () => _apply(_draft.copyWith(look: look.withPart(part, v))),
              ),
          ],
        );

    Widget dial(TamaDial d, String label) => _DialRow(
          key: ValueKey<String>('creator.${d.name}'),
          label: label,
          value: look.dial(d),
          onChangeStart: _checkpoint,
          onChanged: (v) => _apply(_draft.copyWith(look: _draft.look.withDial(d, v)),
              checkpoint: false),
        );

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 12, top: 4),
          child: Text(text, style: Ty.label.copyWith(fontSize: 14)),
        );

    const faceFocus = Alignment(0, .15);

    final children = switch (_tab) {
      CreatorTab.body => [
          heading(l.tamaShape),
          parts(TamaPart.body),
          const SizedBox(height: 18),
          dial(TamaDial.bodyWidth, l.tamaWidth),
          dial(TamaDial.bodyHeight, l.tamaHeight),
        ],
      CreatorTab.color => [
          IbashoSegmented<TamaColorMode>(
            key: const ValueKey<String>('creator.colorMode'),
            options: [
              (TamaColorMode.palette, l.tamaColorPalette),
              (TamaColorMode.hex, l.tamaColorHex),
            ],
            value: look.colorMode,
            onChanged: (mode) => _apply(_draft.copyWith(look: look.withColor(look.color, mode))),
          ),
          const SizedBox(height: 18),
          if (look.colorMode == TamaColorMode.palette)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (i, c) in T.tamaPalette.indexed)
                  ColorChip(
                    key: ValueKey<String>('creator.palette.$i'),
                    color: c,
                    diameter: 44,
                    selected: hexFromColor(c) == look.color,
                    onPressed: () => _apply(_draft.copyWith(
                        look: look.withColor(hexFromColor(c), TamaColorMode.palette))),
                  ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HsvColorPicker(
                  value: look.bodyColor,
                  width: 330,
                  height: 170,
                  onChangeStart: _checkpoint,
                  onChanged: (c) => _apply(
                    _draft.copyWith(look: _draft.look.withColor(hexFromColor(c), TamaColorMode.hex)),
                    checkpoint: false,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: IbashoTextField(
                    key: const ValueKey<String>('creator.hex'),
                    controller: _hex,
                    label: l.tamaColorHexField,
                    hint: '#RRGGBB',
                    maxLength: 7,
                    error: _hexError,
                    formatters: [FilteringTextInputFormatter.allow(RegExp('[#0-9A-Fa-f]'))],
                    onChanged: (text) {
                      final clean = text.startsWith('#') ? text : '#$text';
                      if (colorFromHex(clean) != null && clean.length == 7) {
                        _apply(_draft.copyWith(look: look.withColor(clean, TamaColorMode.hex)));
                      }
                    },
                    onSubmitted: (text) {
                      final clean = text.startsWith('#') ? text : '#$text';
                      if (colorFromHex(clean) == null || clean.length != 7) {
                        AudioService.instance.play(Sfx.error);
                        setState(() => _hexError = l.tamaColorHexError);
                      }
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 22),
          const Hairline(),
          const SizedBox(height: 16),
          heading(l.tamaPattern),
          parts(TamaPart.pattern),
          const SizedBox(height: 18),
          dial(TamaDial.patternTone, l.tamaPatternTone),
        ],
      CreatorTab.eyes => [
          heading(l.tamaStyle),
          parts(TamaPart.eyes, zoom: 2, focus: faceFocus),
          const SizedBox(height: 18),
          dial(TamaDial.eyeSize, l.tamaSize),
          dial(TamaDial.eyeSpacing, l.tamaSpacing),
          dial(TamaDial.eyeHeight, l.tamaHeight),
        ],
      CreatorTab.mouth => [
          heading(l.tamaStyle),
          parts(TamaPart.mouth, zoom: 2.2, focus: faceFocus),
          const SizedBox(height: 18),
          dial(TamaDial.mouthSize, l.tamaSize),
          dial(TamaDial.mouthHeight, l.tamaHeight),
        ],
      CreatorTab.crown => [
          heading(l.tamaStyle),
          parts(TamaPart.crown),
          const SizedBox(height: 18),
          dial(TamaDial.crownSize, l.tamaSize),
        ],
      CreatorTab.cheeks => [
          heading(l.tamaStyle),
          parts(TamaPart.cheeks, zoom: 2, focus: faceFocus),
          const SizedBox(height: 18),
          dial(TamaDial.cheekIntensity, l.tamaIntensity),
        ],
      CreatorTab.limbs => [
          heading(l.tamaArms),
          parts(TamaPart.arms),
          const SizedBox(height: 20),
          heading(l.tamaFeet),
          parts(TamaPart.feet, zoom: 1.6, focus: Alignment.bottomCenter),
        ],
      CreatorTab.character => _characterTab(l),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<Widget> _characterTab(L l) {
    final skin = IbashoSkin.of(context);
    return [
      IbashoTextField(
        key: const ValueKey<String>('creator.name'),
        controller: _name,
        label: l.tamaName,
        hint: l.tamaNameHint,
        maxLength: tamaNameMax,
        error: _nameError,
        width: 360,
        onChanged: (text) {
          _checkpoint();
          setState(() {
            _draft = _draft.copyWith(name: text);
            _nameError = null;
          });
        },
      ),
      const SizedBox(height: 6),
      Text(l.tamaPersonality, style: Ty.label.copyWith(fontSize: 14)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final p in TamaPersonality.values)
            Pressable(
              key: ValueKey<String>('creator.personality.${p.name}'),
              onPressed: _draft.personality == p
                  ? null
                  : () {
                      _apply(_draft.copyWith(personality: p));
                      _view.speak();
                    },
              semanticLabel: personalityLabel(l, p),
              builder: (context, state) {
                final selected = _draft.personality == p;
                return FocusRing(
                  visible: state.focus,
                  radius: 18,
                  child: SizedBox(
                    width: 196,
                    height: 76,
                    child: GlossSurfaceCard(
                      selected: selected,
                      hover: state.hover,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            personalityLabel(l, p),
                            style: Ty.body.copyWith(
                              fontWeight: FontWeight.w500,
                              color: selected ? skin.accentDeep : T.ink,
                            ),
                          ),
                          Text(
                            personalityHint(l, p),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Ty.micro.copyWith(height: 1.25),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 22),
      const Hairline(),
      const SizedBox(height: 16),
      Row(
        children: [
          Text(l.tamaVoice, style: Ty.label.copyWith(fontSize: 14)),
          const Spacer(),
          IbashoButton(
            key: const ValueKey<String>('creator.listen'),
            label: l.tamaListen,
            glyph: Glyph.wave,
            height: 40,
            cue: null,
            onPressed: () => _view.speak(),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _DialRow(
        key: const ValueKey<String>('creator.pitch'),
        label: l.tamaVoicePitch,
        value: _draft.voice.pitch,
        onChangeStart: _checkpoint,
        onChanged: (v) => _apply(_draft.copyWith(voice: _draft.voice.copyWith(pitch: v)),
            checkpoint: false),
      ),
      _DialRow(
        key: const ValueKey<String>('creator.tempo'),
        label: l.tamaVoiceTempo,
        value: _draft.voice.tempo,
        onChangeStart: _checkpoint,
        onChanged: (v) => _apply(_draft.copyWith(voice: _draft.voice.copyWith(tempo: v)),
            checkpoint: false),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(l.tamaVoiceTimbre, style: Ty.body),
      ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in TamaTimbre.values)
            Pressable(
              key: ValueKey<String>('creator.timbre.${t.name}'),
              onPressed: () {
                if (_draft.voice.timbre != t) {
                  _apply(_draft.copyWith(voice: _draft.voice.copyWith(timbre: t)));
                }
                _view.speak();
              },
              semanticLabel: timbreLabel(l, t),
              builder: (context, state) {
                final selected = _draft.voice.timbre == t;
                return FocusRing(
                  visible: state.focus,
                  radius: 20,
                  child: SizedBox(
                    height: 40,
                    child: GlossSurface(
                      radius: 20,
                      tint: selected ? skin.accent : null,
                      elevation: selected ? .9 : .7 + state.hover * .5,
                      borderColor: selected ? skin.accentDeep : Color.lerp(T.hairline, skin.accent, state.hover)!,
                      sink: state.press * 1.2,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          timbreLabel(l, t),
                          style: Ty.body.copyWith(
                            color: selected ? T.onAccent : T.ink,
                            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text(l.tamaVoiceHint, style: Ty.caption),
    ];
  }
}

/// Fila de deslizador: etiqueta, raíl y valor.
class _DialRow extends StatelessWidget {
  const _DialRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback? onChangeStart;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label, style: Ty.body)),
            IbashoSlider(
              value: value / 100,
              width: 330,
              ticks: 20,
              semanticLabel: label,
              onChangeStart: onChangeStart,
              onChanged: (f) => onChanged((f * 100).round()),
            ),
            SizedBox(
              width: 52,
              child: Text(
                '$value',
                textAlign: TextAlign.right,
                style: Ty.numeral(17, color: T.inkSoft),
              ),
            ),
          ],
        ),
      );
}

/// Pestañas del creador: una fila de pastillas, la elegida tenida de acento.
class _TabRail extends StatelessWidget {
  const _TabRail({required this.value, required this.onChanged});

  final CreatorTab value;
  final ValueChanged<CreatorTab> onChanged;

  static String _label(L l, CreatorTab tab) => switch (tab) {
        CreatorTab.body => l.tamaTabBody,
        CreatorTab.color => l.tamaTabColor,
        CreatorTab.eyes => l.tamaTabEyes,
        CreatorTab.mouth => l.tamaTabMouth,
        CreatorTab.crown => l.tamaTabCrown,
        CreatorTab.cheeks => l.tamaTabCheeks,
        CreatorTab.limbs => l.tamaTabLimbs,
        CreatorTab.character => l.tamaTabCharacter,
      };

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    return SizedBox(
      height: 46,
      child: GlossSurface(
        radius: 23,
        recessed: true,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final tab in CreatorTab.values)
              Expanded(
                flex: tab == CreatorTab.limbs ? 14 : 10,
                child: Pressable(
                  key: ValueKey<String>('creator.tab.${tab.name}'),
                  onPressed: tab == value ? null : () => onChanged(tab),
                  semanticLabel: _label(l, tab),
                  builder: (context, state) {
                    final selected = tab == value;
                    final text = Text(
                      _label(l, tab),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.caption.copyWith(
                        fontSize: 14,
                        color: selected
                            ? T.onAccent
                            : Color.lerp(T.inkSoft, skin.accentDeep, state.hover),
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    );
                    return selected
                        ? GlossSurface(
                            radius: 19,
                            tint: skin.accent,
                            elevation: .9,
                            borderColor: skin.accentDeep,
                            child: Center(child: text),
                          )
                        : Center(child: text);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta seleccionable de plastico: blanca, o lavada de acento si esta
/// elegida.
class GlossSurfaceCard extends StatelessWidget {
  const GlossSurfaceCard({
    super.key,
    required this.selected,
    required this.hover,
    required this.child,
  });

  final bool selected;
  final double hover;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Transform.translate(
      offset: Offset(0, selected ? 0 : -2 * hover),
      child: GlossSurface(
        radius: 18,
        tint: selected ? skin.accentWash : null,
        elevation: selected ? 1.2 : .8 + hover * .6,
        borderWidth: selected ? 2.2 : 1,
        borderColor: selected ? skin.accentDeep : T.hairline,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: child,
      ),
    );
  }
}
