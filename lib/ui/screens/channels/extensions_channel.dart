// Ibasho — gestión local de extensiones IES.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../extensions/addon_manager.dart';
import '../../../extensions/backdrop_pack.dart';
import '../../../extensions/content_registry.dart';
import '../../../extensions/extension_error.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';
import 'kobo_content_channel.dart';

class ExtensionsChannel extends ConsumerStatefulWidget {
  const ExtensionsChannel({super.key});

  @override
  ConsumerState<ExtensionsChannel> createState() => _ExtensionsChannelState();
}

class _ExtensionsChannelState extends ConsumerState<ExtensionsChannel> {
  late final Future<AddonManager> _manager = AddonManager.open();
  late Future<List<_ExtensionView>> _snapshot = _load();
  bool _mutating = false;

  Future<List<_ExtensionView>> _load() async {
    final manager = await _manager;
    final installed = await manager.listInstalled();
    final views = <_ExtensionView>[];
    for (final extension in installed) {
      views.add(
        _ExtensionView(
          installed: extension,
          versions: await manager.listInstalledVersions(extension.manifest.id),
        ),
      );
    }
    return views;
  }

  void _reload() {
    if (!mounted) return;
    final nextSnapshot = _load();
    setState(() {
      _snapshot = nextSnapshot;
    });
  }

  Future<void> _install() async {
    if (_mutating) return;
    const type = XTypeGroup(label: 'Ibasho', extensions: <String>['ibasho']);
    final l = L.of(context)!;
    XFile? selected;
    try {
      selected = await openFile(acceptedTypeGroups: const <XTypeGroup>[type]);
    } catch (error, stack) {
      debugPrint('Kobo picker error: $error\n$stack');
      if (mounted) {
        showIbashoToast(
          context,
          '${l.extensionsPickerFailed} (${error.runtimeType})',
          isError: true,
        );
      }
      return;
    }
    if (selected == null || !mounted) return;

    setState(() => _mutating = true);
    try {
      final manager = await _manager;
      final installed = await manager.install(File(selected.path));
      if (!mounted) return;
      showIbashoToast(
        context,
        l.extensionsInstalled(
          installed.manifest.name,
          installed.manifest.version.toString(),
        ),
      );
      await _reconcileRuntime();
      _reload();
    } on ExtensionException catch (error) {
      if (mounted) {
        showIbashoToast(
          context,
          l.extensionsInstallFailed(error.message),
          isError: true,
        );
      }
    } catch (error, stack) {
      debugPrint('Kobo install unexpected error: $error\n$stack');
      if (mounted) {
        showIbashoToast(
          context,
          '${l.extensionsUnexpectedError} (${error.runtimeType})',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _setEnabled(_ExtensionView view, bool enabled) async {
    await _mutate(() async {
      final manager = await _manager;
      await manager.setEnabled(view.installed.manifest.id, enabled);
    });
  }

  Future<void> _uninstall(_ExtensionView view) async {
    if (_mutating) return;
    final l = L.of(context)!;
    final manifest = view.installed.manifest;
    final confirmed = await askConfirmation(
      context,
      title: l.extensionsRemoveTitle(manifest.name),
      body: l.extensionsRemoveBody,
      confirmLabel: l.extensionsRemove,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!confirmed || !mounted) return;

    await _mutate(() async {
      final manager = await _manager;
      await manager.uninstall(manifest.id);
    }, success: l.extensionsRemoved(manifest.name));
  }

  Future<void> _chooseVersion(_ExtensionView view) async {
    if (_mutating || view.versions.length < 2) return;
    final l = L.of(context)!;
    final manifest = view.installed.manifest;
    final chosen = await showIbashoModal<String>(
      context,
      (dialogContext) => IbashoDialog(
        width: 620,
        title: l.extensionsRollbackTitle(manifest.name),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.extensionsRollbackBody, style: Ty.caption),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final version in view.versions)
                  IbashoButton(
                    label: version.active
                        ? l.extensionsActiveVersion(
                            version.manifest.version.toString(),
                          )
                        : version.manifest.version.toString(),
                    tone: version.active ? ButtonTone.accent : ButtonTone.plain,
                    glyph: version.active ? Glyph.check : Glyph.refresh,
                    onPressed: version.active
                        ? null
                        : () => Navigator.of(
                            dialogContext,
                          ).pop(version.manifest.version.toString()),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IbashoButton(
            label: l.actionClose,
            tone: ButtonTone.quiet,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    await _mutate(() async {
      final manager = await _manager;
      await manager.activateVersion(manifest.id, chosen);
    }, success: l.extensionsRollbackDone(manifest.name, chosen));
  }

  Future<void> _mutate(
    Future<void> Function() action, {
    String? success,
  }) async {
    if (_mutating) return;
    final l = L.of(context)!;
    setState(() => _mutating = true);
    try {
      await action();
      if (!mounted) return;
      if (success != null) showIbashoToast(context, success);
      await _reconcileRuntime();
      _reload();
    } on ExtensionException catch (error) {
      if (mounted) {
        showIbashoToast(
          context,
          l.extensionsActionFailed(error.message),
          isError: true,
        );
      }
    } catch (error, stack) {
      debugPrint('Kobo mutation unexpected error: $error\n$stack');
      if (mounted) {
        showIbashoToast(
          context,
          '${l.extensionsUnexpectedError} (${error.runtimeType})',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _reconcileRuntime() async {
    ref.invalidate(extensionContentProvider);
    ref.invalidate(extensionBackdropsProvider);
    final registry = await ref.read(extensionContentProvider.future);

    final preferences = ref.read(preferencesProvider);
    final musicId = preferences.musicTrack;
    if (!musicId.startsWith('ext:')) return;

    final track = registry.musicByPreferenceId(musicId);
    final controller = ref.read(preferencesProvider.notifier);
    if (track == null) {
      await controller.setMusicTrack(MusicTrack.fallback.id);
    } else {
      await controller.setExtensionMusicTrack(
        track.preferenceId,
        track.filePath,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);

    return ChannelScaffold(
      title: l.extensionsTitle,
      glyph: Glyph.download,
      trailing: IbashoButton(
        label: _mutating ? l.extensionsWorking : l.extensionsInstall,
        glyph: Glyph.download,
        tone: ButtonTone.accent,
        height: layout.tall ? 44 : 42,
        onPressed: _mutating ? null : _install,
      ),
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          layout.pick(28, 18),
          layout.gutter,
          44,
        ),
        child: Center(
          child: SizedBox(
            width: layout.pick(880, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: GlyphIcon(
                          Glyph.lock,
                          size: 22,
                          color: Ty.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.extensionsSafetyTitle, style: Ty.body),
                            const SizedBox(height: 4),
                            Text(l.extensionsSafetyBody, style: Ty.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  child: Row(
                    children: [
                      const GlyphIcon(Glyph.star, size: 22, color: T.cyan),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          Localizations.localeOf(
                                context,
                              ).languageCode.startsWith('en')
                              ? 'Browse active Kōbō content, previews and games.'
                              : 'Explora contenido Kōbō activo, vistas previas y juegos.',
                          style: Ty.caption,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IbashoButton(
                        label:
                            Localizations.localeOf(
                              context,
                            ).languageCode.startsWith('en')
                            ? 'content'
                            : 'contenido',
                        glyph: Glyph.star,
                        onPressed: () => pushChannelPage<void>(
                          context,
                          (_) => const KoboContentChannel(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                FutureBuilder<List<_ExtensionView>>(
                  future: _snapshot,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return SectionCard(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(l.loading, style: Ty.lead),
                          ),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.extensionsLoadFailed, style: Ty.body),
                            const SizedBox(height: 8),
                            Text(
                              snapshot.error.toString(),
                              style: Ty.caption,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            IbashoButton(
                              label: l.actionRetry,
                              glyph: Glyph.refresh,
                              onPressed: _reload,
                            ),
                          ],
                        ),
                      );
                    }

                    final extensions =
                        snapshot.data ?? const <_ExtensionView>[];
                    if (extensions.isEmpty) {
                      return SectionCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            children: [
                              GlyphIcon(
                                Glyph.download,
                                size: 38,
                                color: Ty.inkSoft,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l.extensionsEmptyTitle,
                                style: Ty.lead,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l.extensionsEmptyBody,
                                style: Ty.caption,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: [
                        for (var i = 0; i < extensions.length; i++) ...[
                          _ExtensionCard(
                            view: extensions[i],
                            busy: _mutating,
                            onEnabled: (value) =>
                                _setEnabled(extensions[i], value),
                            onVersions: () => _chooseVersion(extensions[i]),
                            onRemove: () => _uninstall(extensions[i]),
                          ),
                          if (i != extensions.length - 1)
                            const SizedBox(height: 18),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExtensionView {
  const _ExtensionView({required this.installed, required this.versions});

  final InstalledExtension installed;
  final List<InstalledExtensionVersion> versions;
}

class _ExtensionCard extends StatelessWidget {
  const _ExtensionCard({
    required this.view,
    required this.busy,
    required this.onEnabled,
    required this.onVersions,
    required this.onRemove,
  });

  final _ExtensionView view;
  final bool busy;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onVersions;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final extension = view.installed;

    final actions = <Widget>[
      IbashoButton(
        label: l.extensionsVersions,
        glyph: Glyph.refresh,
        height: 42,
        onPressed: busy || view.versions.length < 2 ? null : onVersions,
      ),
      IbashoButton(
        label: l.extensionsRemove,
        glyph: Glyph.trash,
        tone: ButtonTone.warn,
        height: 42,
        onPressed: busy ? null : onRemove,
      ),
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!layout.tall)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _ExtensionIdentity(view: view)),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      extension.enabled
                          ? l.extensionsEnabled
                          : l.extensionsDisabled,
                      style: Ty.caption,
                    ),
                    const SizedBox(height: 6),
                    IbashoToggle(
                      value: extension.enabled,
                      onChanged: busy ? null : onEnabled,
                    ),
                  ],
                ),
              ],
            )
          else ...[
            _ExtensionIdentity(view: view),
            const SizedBox(height: 16),
            SettingRow(
              label: extension.enabled
                  ? l.extensionsEnabled
                  : l.extensionsDisabled,
              divider: false,
              control: IbashoToggle(
                value: extension.enabled,
                onChanged: busy ? null : onEnabled,
              ),
            ),
          ],
          const SizedBox(height: 18),
          const Hairline(),
          const SizedBox(height: 16),
          Text(
            l.extensionsTrustLocalUnsigned,
            style: Ty.caption.copyWith(color: T.warn),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ),
    );
  }
}

class _ExtensionIdentity extends StatelessWidget {
  const _ExtensionIdentity({required this.view});

  final _ExtensionView view;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final manifest = view.installed.manifest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          manifest.name,
          style: Ty.lead.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 3),
        Text(manifest.id, style: Ty.micro),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 5,
          children: [
            Text(
              l.extensionsVersion(manifest.version.toString()),
              style: Ty.caption,
            ),
            Text(l.extensionsPublisher(manifest.publisher), style: Ty.caption),
            Text(
              l.extensionsVersionCount(view.versions.length),
              style: Ty.caption,
            ),
          ],
        ),
      ],
    );
  }
}
