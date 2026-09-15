// Ibasho — canal de administracion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/errors.dart';
import '../../../backend/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/admin.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../failure_text.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';
import '../channel_route.dart';

class AdminChannel extends ConsumerStatefulWidget {
  const AdminChannel({super.key});

  @override
  ConsumerState<AdminChannel> createState() => _AdminChannelState();
}

class _AdminChannelState extends ConsumerState<AdminChannel> {
  final TextEditingController _username = TextEditingController();

  String _password = '';
  String? _usernameError;
  ProvisionedAccount? _credential;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final l = L.of(context)!;
    final username = _username.text.trim().toLowerCase();
    if (!usernamePattern.hasMatch(username)) {
      AudioService.instance.play(Sfx.error);
      setState(() => _usernameError = l.adminErrorUsernameInvalid);
      return;
    }
    setState(() => _usernameError = null);

    try {
      final account = await ref
          .read(adminProvider.notifier)
          .createAccount(username, password: _password.isEmpty ? null : _password);
      if (!mounted) return;
      AudioService.instance.play(Sfx.open);
      setState(() {
        _credential = account;
        _username.clear();
        _password = '';
      });
    } on IbashoException catch (e) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      setState(() => _usernameError = e.failure == IbashoFailure.usernameTaken
          ? l.adminErrorUsernameTaken
          : messageForFailure(l, e.failure));
    } catch (_) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      setState(() => _usernameError = l.adminErrorCreate);
    }
  }

  Future<void> _regenerate(AllowlistEntry entry) async {
    final l = L.of(context)!;
    final confirmed = await askConfirmation(
      context,
      title: l.adminRegenerateConfirmTitle,
      body: l.adminRegenerateConfirmBody(entry.username),
      confirmLabel: l.adminRegenerate,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!confirmed || !mounted) return;
    try {
      final account =
          await ref.read(adminProvider.notifier).regenerateCredential(entry);
      if (!mounted) return;
      AudioService.instance.play(Sfx.open);
      setState(() => _credential = account);
    } on IbashoException catch (e) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, messageForFailure(l, e.failure), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final localeCode = ref.watch(preferencesProvider.select((p) => p.localeCode));
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));
    final state = ref.watch(adminProvider);

    if (!isAdmin) {
      return ChannelScaffold(
        title: l.adminTitle,
        glyph: Glyph.keycard,
        child: Center(child: Text(l.adminNotAdmin, style: Ty.lead)),
      );
    }

    return ChannelScaffold(
      title: l.adminTitle,
      glyph: Glyph.keycard,
      child: IbashoScroll(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 44),
        child: Center(
          child: SizedBox(
            width: 900,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: l.adminCreateSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: IbashoTextField(
                              controller: _username,
                              label: l.adminUsername,
                              hint: l.adminUsernameHint,
                              maxLength: 16,
                              error: _usernameError,
                              formatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[a-z0-9_]')),
                              ],
                              onSubmitted: (_) => _create(),
                            ),
                          ),
                          const SizedBox(width: 20),
                          Padding(
                            padding: const EdgeInsets.only(top: 25),
                            child: IbashoButton(
                              label: l.adminGenerate,
                              glyph: Glyph.dice,
                              height: 48,
                              onPressed: () =>
                                  setState(() => _password = generatePassword()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Padding(
                            padding: const EdgeInsets.only(top: 25),
                            child: IbashoButton(
                              label: state.busy ? l.adminCreating : l.adminCreate,
                              glyph: Glyph.plus,
                              tone: ButtonTone.accent,
                              height: 48,
                              cue: null,
                              onPressed: state.busy ? null : _create,
                            ),
                          ),
                        ],
                      ),
                      if (_password.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              const GlyphIcon(Glyph.lock, size: 18, color: T.inkSoft),
                              const SizedBox(width: 10),
                              Text(_password, style: Ty.credential.copyWith(fontSize: 17)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_credential != null) ...[
                  const SizedBox(height: 22),
                  _CredentialCard(
                    account: _credential!,
                    onDismiss: () => setState(() => _credential = null),
                  ),
                ],
                const SizedBox(height: 22),
                SectionCard(
                  title: l.adminListSection,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 10),
                  child: state.loading
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(child: Text(l.loading, style: Ty.caption)),
                        )
                      : state.accounts.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 30),
                              child: Center(
                                  child: Text(l.adminListEmpty, style: Ty.caption)),
                            )
                          : Column(
                              children: [
                                for (var i = 0; i < state.accounts.length; i++) ...[
                                  if (i > 0) const Hairline(),
                                  _AccountRow(
                                    entry: state.accounts[i],
                                    localeCode: localeCode,
                                    busy: state.busy,
                                    onToggle: (value) => ref
                                        .read(adminProvider.notifier)
                                        .setDisabled(state.accounts[i], value),
                                    onRegenerate: () =>
                                        _regenerate(state.accounts[i]),
                                  ),
                                ],
                              ],
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloque copiable con la credencial recien emitida.
class _CredentialCard extends StatelessWidget {
  const _CredentialCard({required this.account, required this.onDismiss});

  final ProvisionedAccount account;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final block = '${l.loginUsername}: ${account.username}\n'
        '${l.loginPassword}: ${account.password}';

    return GlossSurface(
      radius: 26,
      tint: T.warn,
      elevation: 1.6,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlyphIcon(Glyph.keycard, size: 24, color: T.onAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.adminCredentialTitle(account.username),
                  style: Ty.lead.copyWith(color: T.onAccent),
                ),
              ),
              IconPill(
                glyph: Glyph.cross,
                diameter: 36,
                cue: Sfx.back,
                onPressed: onDismiss,
              ),
            ],
          ),
          const SizedBox(height: 16),
          GlossSurface(
            radius: 16,
            recessed: true,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l.loginUsername}   ${account.username}',
                    style: Ty.credential),
                Text('${l.loginPassword}   ${account.password}',
                    style: Ty.credential),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.adminCredentialWarning,
                  style: Ty.caption.copyWith(color: T.onAccent),
                ),
              ),
              IbashoButton(
                label: l.adminCopyBlock,
                glyph: Glyph.copy,
                height: 44,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: block));
                  if (!context.mounted) return;
                  showIbashoToast(context, l.actionCopied);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.entry,
    required this.localeCode,
    required this.busy,
    required this.onToggle,
    required this.onRegenerate,
  });

  final AllowlistEntry entry;
  final String localeCode;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final stateLabel = entry.disabled
        ? l.adminStateDisabled
        : entry.mustChangePassword
            ? l.adminStatePending
            : l.adminStateEnabled;
    final stateColor = entry.disabled
        ? T.inkSoft
        : entry.mustChangePassword
            ? T.warn
            : skin.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: GlossSurface(
              radius: 13,
              tint: entry.disabled ? null : skin.accent,
              recessed: entry.disabled,
              child: Center(
                child: GlyphIcon(
                  Glyph.person,
                  size: 21,
                  color: entry.disabled ? T.inkSoft : T.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.username, style: Ty.body),
                const SizedBox(height: 2),
                Text(
                  l.adminCreatedOn(
                    DateFormat.yMMMd(localeCode).format(entry.createdAt),
                  ),
                  style: Ty.micro,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: stateColor.withValues(alpha: .16),
              border: Border.all(color: stateColor.withValues(alpha: .5)),
            ),
            child: Text(
              stateLabel,
              style: Ty.micro.copyWith(color: T.ink),
            ),
          ),
          const SizedBox(width: 18),
          IbashoButton(
            label: entry.disabled ? l.adminEnable : l.adminDisable,
            height: 40,
            onPressed: busy ? null : () => onToggle(!entry.disabled),
          ),
          const SizedBox(width: 10),
          IbashoButton(
            label: l.adminRegenerate,
            glyph: Glyph.refresh,
            height: 40,
            tone: ButtonTone.quiet,
            cue: null,
            onPressed: busy || entry.disabled ? null : onRegenerate,
          ),
        ],
      ),
    );
  }
}
