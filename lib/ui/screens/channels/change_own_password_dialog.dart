// Ibasho — cambio de contrasena voluntario, desde Ajustes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/errors.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../failure_text.dart';
import '../../widgets/controls.dart';
import '../../widgets/overlays.dart';
import '../../widgets/text_field.dart';
import '../change_password_screen.dart' show minimumPasswordLength;

/// Abre el dialogo. Devuelve `true` si la contrasena se cambio.
Future<bool> showChangeOwnPassword(BuildContext context) async =>
    await showIbashoModal<bool>(
      context,
      (_) => const _ChangeOwnPasswordDialog(),
    ) ??
    false;

class _ChangeOwnPasswordDialog extends ConsumerStatefulWidget {
  const _ChangeOwnPasswordDialog();

  @override
  ConsumerState<_ChangeOwnPasswordDialog> createState() =>
      _ChangeOwnPasswordDialogState();
}

class _ChangeOwnPasswordDialogState
    extends ConsumerState<_ChangeOwnPasswordDialog> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  final FocusNode _firstNode = FocusNode();
  final FocusNode _secondNode = FocusNode();

  String? _error;
  bool _working = false;

  @override
  void dispose() {
    _current.dispose();
    _first.dispose();
    _second.dispose();
    _firstNode.dispose();
    _secondNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    final l = L.of(context)!;

    String? problem;
    if (_current.text.isEmpty) {
      problem = l.changeOwnPasswordWrongCurrent;
    } else if (_first.text.length < minimumPasswordLength) {
      problem = l.changePasswordErrorShort(minimumPasswordLength);
    } else if (_first.text != _second.text) {
      problem = l.changePasswordErrorMismatch;
    } else if (_first.text == _current.text) {
      problem = l.changePasswordErrorSame;
    }
    if (problem != null) {
      AudioService.instance.play(Sfx.error);
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).changeOwnPassword(
            currentPassword: _current.text,
            newPassword: _first.text,
          );
      if (!mounted) return;
      AudioService.instance.play(Sfx.open);
      Navigator.of(context).pop(true);
    } on IbashoException catch (e) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      setState(() => _error = e.failure == IbashoFailure.invalidCredentials
          ? l.changeOwnPasswordWrongCurrent
          : messageForFailure(l, e.failure));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    return IbashoDialog(
      title: l.changeOwnPasswordTitle,
      width: 540,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          IbashoTextField(
            controller: _current,
            label: l.changeOwnPasswordCurrent,
            obscure: true,
            autofocus: true,
            enabled: !_working,
            maxLength: 64,
            onSubmitted: (_) => _firstNode.requestFocus(),
          ),
          IbashoTextField(
            controller: _first,
            focusNode: _firstNode,
            label: l.changePasswordNew,
            obscure: true,
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
            height: 22,
            child: _error == null
                ? null
                : Text(_error!, style: Ty.caption.copyWith(color: T.warn)),
          ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
        ),
        IbashoButton(
          label: _working ? l.changePasswordWorking : l.actionSave,
          tone: ButtonTone.accent,
          minWidth: 140,
          cue: null,
          onPressed: _working ? null : _submit,
        ),
      ],
    );
  }
}
