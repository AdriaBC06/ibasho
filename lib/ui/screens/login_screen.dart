// Ibasho — inicio de sesion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_service.dart';
import '../../backend/errors.dart';
import '../../core/device.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../failure_text.dart';
import '../layout.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/logo.dart';
import '../widgets/panel.dart';
import '../widgets/text_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _usernameNode = FocusNode();
  final FocusNode _passwordNode = FocusNode();

  String? _error;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _username.text = ref.read(preferencesProvider).lastUsername;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameNode.dispose();
    _passwordNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_working) return;
    final l = L.of(context)!;
    final username = _username.text.trim();
    final password = _password.text;

    if (username.isEmpty || password.isEmpty) {
      AudioService.instance.play(Sfx.error);
      setState(() => _error = l.loginErrorEmpty);
      return;
    }

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(username: username, password: password);
      AudioService.instance.play(Sfx.open);
    } on IbashoException catch (e) {
      AudioService.instance.play(Sfx.error);
      if (mounted) setState(() => _error = messageForFailure(l, e.failure));
    } catch (_) {
      AudioService.instance.play(Sfx.error);
      if (mounted) setState(() => _error = l.loginErrorUnknown);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final reason = ref.watch(sessionProvider.select((s) => s.reason));
    final notice = _error ?? messageForSignOut(l, reason);
    final layout = Layout.of(context);

    return Bezel(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IbashoMark(size: layout.pick(76, 60), accent: skin.accent),
                SizedBox(width: layout.pick(20, 14)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.appName, style: Ty.logo(layout.pick(40, 32), T.ink)),
                    Text('居場所', style: Ty.logoJa(layout.pick(17, 15), T.inkSoft)),
                  ],
                ),
              ],
            ),
            SizedBox(height: layout.pick(34, 22)),
            SizedBox(
              width: math.min(560, layout.width - layout.gutter * 2),
              child: ScreenPanel(
                child: Padding(
                  padding: layout.pick(
                    const EdgeInsets.fromLTRB(46, 36, 46, 34),
                    const EdgeInsets.fromLTRB(26, 28, 26, 26),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.loginTitle, style: Ty.title),
                      const SizedBox(height: 4),
                      Text(l.loginSubtitle, style: Ty.caption),
                      SizedBox(height: layout.pick(26, 16)),
                      IbashoTextField(
                        controller: _username,
                        focusNode: _usernameNode,
                        label: l.loginUsername,
                        // En el movil, abrir el teclado solo taparia media
                        // pantalla antes de que se vea donde se ha entrado.
                        autofocus: !Device.isAndroid,
                        enabled: !_working,
                        maxLength: 16,
                        formatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                        ],
                        onSubmitted: (_) => _passwordNode.requestFocus(),
                      ),
                      IbashoTextField(
                        controller: _password,
                        focusNode: _passwordNode,
                        label: l.loginPassword,
                        obscure: true,
                        enabled: !_working,
                        maxLength: 64,
                        onSubmitted: (_) => _submit(),
                      ),
                      SizedBox(
                        height: 40,
                        child: notice == null
                            ? null
                            : _Notice(message: notice, accent: skin.accent),
                      ),
                      const SizedBox(height: 6),
                      IbashoButton(
                        label: _working ? l.loginWorking : l.loginSubmit,
                        tone: ButtonTone.accent,
                        expand: true,
                        height: layout.pick(54, 52),
                        cue: Sfx.open,
                        onPressed: _working ? null : _submit,
                      ),
                      SizedBox(height: layout.pick(16, 12)),
                      Text(
                        l.loginForgotHint,
                        textAlign: TextAlign.center,
                        style: Ty.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Aviso de error bajo el formulario.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.accent});

  final String message;
  final Color accent;

  @override
  Widget build(BuildContext context) => GlossSurface(
        radius: 14,
        recessed: true,
        tint: T.warn,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            const GlyphIcon(Glyph.cross, size: 17, color: T.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Ty.caption.copyWith(color: T.ink, height: 1.25),
              ),
            ),
          ],
        ),
      );
}
