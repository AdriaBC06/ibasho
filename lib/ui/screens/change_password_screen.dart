// Ibasho — cambio obligatorio de contrasena en el primer acceso.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/errors.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../failure_text.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/panel.dart';
import '../widgets/text_field.dart';

/// Longitud minima. Firebase exige seis; Ibasho pide algo mas.
const int minimumPasswordLength = 10;

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  final FocusNode _firstNode = FocusNode();
  final FocusNode _secondNode = FocusNode();

  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _firstNode.dispose();
    _secondNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    final l = L.of(context)!;
    final password = _first.text;

    if (password.length < minimumPasswordLength) {
      AudioService.instance.play(Sfx.error);
      setState(() => _error = l.changePasswordErrorShort(minimumPasswordLength));
      return;
    }
    if (password != _second.text) {
      AudioService.instance.play(Sfx.error);
      setState(() => _error = l.changePasswordErrorMismatch);
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).completePasswordChange(password);
      AudioService.instance.play(Sfx.open);
    } on IbashoException catch (e) {
      AudioService.instance.play(Sfx.error);
      if (mounted) setState(() => _error = messageForFailure(l, e.failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final username = ref.watch(sessionProvider.select((s) => s.username));

    return Bezel(
      child: Center(
        child: SizedBox(
          width: 580,
          child: ScreenPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(46, 38, 46, 34),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: GlossSurface(
                          radius: 18,
                          tint: skin.accent,
                          child: const Center(
                            child: GlyphIcon(Glyph.lock,
                                size: 26, color: T.onAccent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(l.changePasswordTitle, style: Ty.title),
                            const SizedBox(height: 2),
                            Text(
                              l.changePasswordSubtitle,
                              style: Ty.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 18),
                    child: Text(username, style: Ty.lead),
                  ),
                  IbashoTextField(
                    controller: _first,
                    focusNode: _firstNode,
                    label: l.changePasswordNew,
                    obscure: true,
                    autofocus: true,
                    enabled: !_working,
                    maxLength: 64,
                    onSubmitted: (_) => _secondNode.requestFocus(),
                  ),
                  IbashoTextField(
                    controller: _second,
                    focusNode: _secondNode,
                    label: l.changePasswordRepeat,
                    obscure: true,
                    enabled: !_working,
                    maxLength: 64,
                    onSubmitted: (_) => _submit(),
                  ),
                  SizedBox(
                    height: 38,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: Ty.caption.copyWith(color: T.warn),
                          ),
                  ),
                  IbashoButton(
                    label: _working
                        ? l.changePasswordWorking
                        : l.changePasswordSubmit,
                    tone: ButtonTone.accent,
                    expand: true,
                    height: 54,
                    cue: Sfx.open,
                    onPressed: _working ? null : _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
