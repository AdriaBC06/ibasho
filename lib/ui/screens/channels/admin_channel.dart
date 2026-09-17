// Ibasho — canal de administracion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/errors.dart';
import '../../../backend/models.dart';
import '../../../core/version.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/admin.dart';
import '../../../state/coins.dart';
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../state/update_gate.dart';
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
import '../../layout.dart';
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

    final layout = Layout.of(context);

    return ChannelScaffold(
      title: l.adminTitle,
      glyph: Glyph.keycard,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(28, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(900, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: l.adminCreateSection,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // En vertical el campo se lleva su fila y los dos
                      // botones van debajo.
                      _Rows(
                        tall: layout.tall,
                        field: IbashoTextField(
                          controller: _username,
                          label: l.adminUsername,
                          hint: l.adminUsernameHint,
                          maxLength: 16,
                          error: _usernameError,
                          formatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                          ],
                          onSubmitted: (_) => _create(),
                        ),
                        actions: [
                          IbashoButton(
                            label: l.adminGenerate,
                            glyph: Glyph.dice,
                            height: 48,
                            expand: layout.tall,
                            onPressed: () => setState(() => _password = generatePassword()),
                          ),
                          IbashoButton(
                            label: state.busy ? l.adminCreating : l.adminCreate,
                            glyph: Glyph.plus,
                            tone: ButtonTone.accent,
                            height: 48,
                            expand: layout.tall,
                            cue: null,
                            onPressed: state.busy ? null : _create,
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
                const _VersionLock(),
                const SizedBox(height: 22),
                const _GlobalGroupSection(),
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

/// El grupo Global. No se pueden crear grupos desde la app: este lo crea el
/// admin una sola vez y a partir de ahi cada cual se une si quiere.
class _GlobalGroupSection extends ConsumerStatefulWidget {
  const _GlobalGroupSection();

  @override
  ConsumerState<_GlobalGroupSection> createState() => _GlobalGroupSectionState();
}

class _GlobalGroupSectionState extends ConsumerState<_GlobalGroupSection> {
  bool _working = false;

  Future<void> _create() async {
    final l = L.of(context)!;
    setState(() => _working = true);
    final ok = await ref.read(adminProvider.notifier).createGlobalGroup();
    if (!mounted) return;
    setState(() => _working = false);
    AudioService.instance.play(ok ? Sfx.open : Sfx.error);
    showIbashoToast(
      context,
      ok ? l.adminGroupCreated : l.adminGroupError,
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final group = ref.watch(messagesProvider.select((m) => m.global));

    return SectionCard(
      title: l.adminGroupSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            group == null ? l.groupMissing : l.adminGroupExists,
            style: Ty.caption,
          ),
          const SizedBox(height: 14),
          IbashoButton(
            label: l.adminGroupCreate,
            glyph: Glyph.friends,
            onPressed: group != null || _working ? null : () => unawaited(_create()),
          ),
        ],
      ),
    );
  }
}

/// La version minima: quien tenga una anterior ve el aviso de actualizar y no
/// puede entrar. Solo se puede exigir la version de esta build, para que nadie
/// se quede fuera de su propio panel.
class _VersionLock extends ConsumerStatefulWidget {
  const _VersionLock();

  @override
  ConsumerState<_VersionLock> createState() => _VersionLockState();
}

class _VersionLockState extends ConsumerState<_VersionLock> {
  final TextEditingController _url = TextEditingController();
  bool _seeded = false;
  bool _working = false;
  String? _urlError;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    final l = L.of(context)!;
    setState(() => _working = true);
    try {
      await action();
      if (!mounted) return;
      AudioService.instance.play(Sfx.open);
      showIbashoToast(context, done);
    } catch (e) {
      if (!mounted) return;
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.adminVersionError, isError: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _require() {
    final l = L.of(context)!;
    final url = _url.text.trim();
    if (url.isNotEmpty && !RegExp(r'^https://\S{1,290}$').hasMatch(url)) {
      AudioService.instance.play(Sfx.error);
      setState(() => _urlError = l.adminVersionUrlInvalid);
      return;
    }
    setState(() => _urlError = null);
    _run(
      () => ref.read(adminProvider.notifier).requireVersion(appVersion, url: url),
      l.adminVersionRequired(appVersion),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final requirement = ref.watch(updateRequirementProvider).valueOrNull;
    if (!_seeded && requirement?.url != null) {
      _url.text = requirement!.url!;
      _seeded = true;
    }
    final current = requirement?.minVersion.toString();

    return SectionCard(
      title: l.adminVersionSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlyphIcon(Glyph.lock, size: 20, color: T.inkSoft),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  current == null ? l.adminVersionNone : l.adminVersionCurrent(current),
                  key: const ValueKey<String>('admin.version.current'),
                  style: Ty.body,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(l.adminVersionHint(appVersion), style: Ty.caption),
          ),
          const SizedBox(height: 16),
          IbashoTextField(
            controller: _url,
            label: l.adminVersionUrl,
            hint: 'https://',
            maxLength: 300,
            error: _urlError,
          ),
          // En vertical los dos botones se reparten en varias lineas si hace
          // falta; en horizontal van en fila, como siempre.
          _Buttons(
            tall: Layout.of(context).tall,
            children: [
              IbashoButton(
                key: const ValueKey<String>('admin.version.require'),
                label: l.adminVersionRequire(appVersion),
                glyph: Glyph.lock,
                height: 46,
                onPressed: _working ? null : _require,
              ),
              if (current != null)
                IbashoButton(
                  key: const ValueKey<String>('admin.version.clear'),
                  label: l.adminVersionClear,
                  tone: ButtonTone.quiet,
                  height: 46,
                  onPressed: _working
                      ? null
                      : () => _run(
                            () => ref.read(adminProvider.notifier).clearRequiredVersion(),
                            l.adminVersionCleared,
                          ),
                ),
            ],
          ),
        ],
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
          // El aviso y el boton de copiar: en vertical uno debajo del otro.
          _Stack(
            tall: Layout.of(context).tall,
            warning: Text(
              l.adminCredentialWarning,
              style: Ty.caption.copyWith(color: T.onAccent),
            ),
            action: IbashoButton(
              label: l.adminCopyBlock,
              glyph: Glyph.copy,
              height: 44,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: block));
                if (!context.mounted) return;
                showIbashoToast(context, l.actionCopied);
              },
            ),
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
    final tall = Layout.of(context).tall;
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

    final buttons = [
      IbashoButton(
        label: entry.disabled ? l.adminEnable : l.adminDisable,
        height: 40,
        expand: tall,
        onPressed: busy ? null : () => onToggle(!entry.disabled),
      ),
      IbashoButton(
        label: l.adminRegenerate,
        glyph: Glyph.refresh,
        height: 40,
        tone: ButtonTone.quiet,
        expand: tall,
        cue: null,
        onPressed: busy || entry.disabled ? null : onRegenerate,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
      Row(
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
          if (!tall) ...[
            const SizedBox(width: 18),
            buttons[0],
            const SizedBox(width: 10),
            buttons[1],
          ],
        ],
      ),
      // En vertical los botones de la cuenta van debajo de sus datos.
      if (tall) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: 10),
            Expanded(child: buttons[1]),
          ],
        ),
      ],
      const SizedBox(height: 10),
      _CoinsField(accountId: entry.accountId, busy: busy),
        ],
      ),
    );
  }
}

/// El campo de alta y sus botones: en fila si hay ancho, en dos filas si no.
/// Las monedas de una cuenta, desde el panel.
///
/// Es el unico sitio de la app donde se escriben: las reglas solo dejan
/// tocarlas a un admin, y a proposito no hay ninguna ruta que permita a una
/// cuenta subirse las suyas. De momento no se gastan en nada, pero el sitio
/// donde darlas tiene que existir antes que aquello en lo que gastarlas.
class _CoinsField extends ConsumerStatefulWidget {
  const _CoinsField({required this.accountId, required this.busy});

  final String accountId;
  final bool busy;

  @override
  ConsumerState<_CoinsField> createState() => _CoinsFieldState();
}

class _CoinsFieldState extends ConsumerState<_CoinsField> {
  final TextEditingController _amount = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _give() async {
    final l = L.of(context)!;
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value < 0 || value > maxCoins) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.adminCoinsError, isError: true);
      return;
    }
    setState(() => _working = true);
    final ok =
        await ref.read(coinsProvider.notifier).setFor(widget.accountId, value);
    if (!mounted) return;
    setState(() => _working = false);
    AudioService.instance.play(ok ? Sfx.open : Sfx.error);
    showIbashoToast(
      context,
      ok ? l.adminCoinsDone : l.adminCoinsError,
      isError: !ok,
    );
    if (ok) _amount.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final current = ref.watch(coinsOfProvider(widget.accountId)).valueOrNull ?? 0;

    return Row(
      children: [
        GlyphIcon(Glyph.coin, size: 16, color: skin.accentDeep),
        const SizedBox(width: 8),
        Text('$current', style: Ty.numeral(14, color: T.inkSoft)),
        const SizedBox(width: 14),
        // Flexible y no de ancho fijo: en la composicion vertical la fila de
        // una cuenta se queda en 264 puntos y un campo de 120 no cabe con el
        // boton al lado.
        Flexible(
          fit: FlexFit.loose,
          child: SizedBox(
            width: 120,
            child: IbashoTextField(
              controller: _amount,
              label: l.adminCoinsAmount,
              enabled: !widget.busy && !_working,
              formatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              maxLength: 9,
              onSubmitted: (_) => unawaited(_give()),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IbashoButton(
          label: l.adminCoinsGive,
          height: 40,
          tone: ButtonTone.quiet,
          cue: null,
          onPressed: widget.busy || _working ? null : () => unawaited(_give()),
        ),
      ],
    );
  }
}

class _Rows extends StatelessWidget {
  const _Rows({required this.tall, required this.field, required this.actions});

  final bool tall;
  final Widget field;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (tall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          field,
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(width: i == 0 ? 20 : 12),
          Padding(padding: const EdgeInsets.only(top: 25), child: actions[i]),
        ],
      ],
    );
  }
}

/// Una fila de botones que en vertical se parte en varias lineas.
class _Buttons extends StatelessWidget {
  const _Buttons({required this.tall, required this.children});

  final bool tall;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => tall
      ? Wrap(spacing: 12, runSpacing: 10, children: children)
      : Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              children[i],
            ],
          ],
        );
}

/// El aviso de la credencial y su boton: al lado en horizontal, apilados en
/// vertical.
class _Stack extends StatelessWidget {
  const _Stack({required this.tall, required this.warning, required this.action});

  final bool tall;
  final Widget warning;
  final Widget action;

  @override
  Widget build(BuildContext context) => tall
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [warning, const SizedBox(height: 12), action],
        )
      : Row(children: [Expanded(child: warning), action]);
}
