// Ibasho — campo de texto propio, montado sobre EditableText.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import 'glyphs.dart';
import 'gloss.dart';
import 'pressable.dart';

/// Campo de texto del entorno.
///
/// Se apoya en `EditableText` en crudo, no en `TextField`, para que no entre
/// nada de Material: ni subrayado, ni relleno, ni tiradores de seleccion, ni
/// menu contextual. Lo que se ve es un hueco hundido de plastico.
class IbashoTextField extends StatefulWidget {
  const IbashoTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.obscure = false,
    this.maxLength,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.error,
    this.width,
    this.formatters = const <TextInputFormatter>[],
    this.multiline = false,
    this.textStyle,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Mensaje bajo el campo. Cuando no es nulo el campo se pinta en ambar.
  final String? error;

  final double? width;
  final List<TextInputFormatter> formatters;
  final bool multiline;

  /// Sustituye al estilo del texto escrito, para campos que se leen de lejos
  /// como el del codigo de amigo. La pista usa el mismo tamaño.
  final TextStyle? textStyle;

  @override
  State<IbashoTextField> createState() => _IbashoTextFieldState();
}

class _IbashoTextFieldState extends State<IbashoTextField>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => widget.enabled;

  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  FocusNode? _ownedNode;
  bool _focused = false;
  bool _revealed = false;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _ownedNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focused != _node.hasFocus) setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final hasError = widget.error != null;
    final obscured = widget.obscure && !_revealed;

    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: _node,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      obscureText: obscured,
      obscuringCharacter: '•',
      maxLines: widget.multiline ? 3 : 1,
      minLines: 1,
      style: (widget.textStyle ?? Ty.body.copyWith(fontSize: 17, height: 1.3))
          .copyWith(color: widget.enabled ? T.ink : T.inkSoft),
      cursorColor: skin.accentDeep,
      backgroundCursorColor: T.inkSoft,
      cursorWidth: 2,
      cursorRadius: const Radius.circular(1),
      cursorOpacityAnimates: !skin.reducedMotion,
      selectionColor: skin.accent.withValues(alpha: .34),
      // Sin controles de seleccion ni menu contextual: en escritorio la
      // seleccion con raton y los atajos de teclado bastan, y asi no aparece
      // ni un widget de Material.
      selectionControls: null,
      contextMenuBuilder: null,
      textInputAction: widget.multiline ? TextInputAction.newline : TextInputAction.done,
      keyboardType: widget.multiline ? TextInputType.multiline : TextInputType.text,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      inputFormatters: [
        if (widget.maxLength != null)
          LengthLimitingTextInputFormatter(widget.maxLength),
        ...widget.formatters,
      ],
      rendererIgnoresPointer: true,
      enableInteractiveSelection: widget.enabled,
      showSelectionHandles: false,
    );

    final accentBorder = hasError
        ? T.warn
        : _focused
            ? skin.accentDeep
            : T.hairline;

    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(widget.label, style: Ty.label),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled ? () => _node.requestFocus() : null,
            child: MouseRegion(
              cursor: widget.enabled
                  ? SystemMouseCursors.text
                  : SystemMouseCursors.basic,
              child: GlossSurface(
                radius: T.fieldRadius,
                recessed: true,
                borderColor: accentBorder,
                borderWidth: _focused || hasError ? 2 : 1,
                tint: hasError ? T.warn : null,
                padding: EdgeInsets.fromLTRB(16, widget.multiline ? 12 : 13, 8,
                    widget.multiline ? 12 : 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          if (widget.hint.isNotEmpty)
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: widget.controller,
                              builder: (context, value, _) => value.text.isEmpty
                                  ? Text(
                                      widget.hint,
                                      style: (widget.textStyle ??
                                              Ty.body.copyWith(fontSize: 17, height: 1.3))
                                          .copyWith(color: T.inkSoft.withValues(alpha: .7)),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          _gestures.buildGestureDetector(
                            behavior: HitTestBehavior.translucent,
                            child: editable,
                          ),
                        ],
                      ),
                    ),
                    if (widget.obscure)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Pressable(
                          onPressed: () => setState(() => _revealed = !_revealed),
                          cue: null,
                          builder: (context, state) => Padding(
                            padding: const EdgeInsets.all(4),
                            child: GlyphIcon(
                              _revealed ? Glyph.eyeOff : Glyph.eye,
                              size: 21,
                              color: Color.lerp(
                                  T.inkSoft, skin.accentDeep, state.hover)!,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 22,
            child: hasError
                ? Padding(
                    padding: const EdgeInsets.only(left: 6, top: 4),
                    child: Text(
                      widget.error!,
                      style: Ty.caption.copyWith(color: T.warn),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
