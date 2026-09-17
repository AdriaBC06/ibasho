// Ibasho — canal de ajustes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../core/version.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../layout.dart';
import '../channel_route.dart';
import '../messages/backup_key.dart';
import '../../track_text.dart';
import '../../widgets/track_tile.dart';
import 'change_own_password_dialog.dart';
import 'credits_channel.dart';

class SettingsChannel extends ConsumerWidget {
  const SettingsChannel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final keyPhrase = ref.watch(identityProvider.select((i) => i.phrase));
    final skin = IbashoSkin.of(context);
    final preferences = ref.watch(preferencesProvider);
    final controller = ref.read(preferencesProvider.notifier);
    final library = ref.watch(musicLibraryProvider);
    final currentTrack = MusicTrack.byId(preferences.musicTrack);
    final layout = Layout.of(context);

    /// Fila de volumen: en vertical el raíl ocupa el ancho entero.
    Widget volume(Glyph glyph, double value, ValueChanged<double> onChanged) => Row(
          mainAxisSize: layout.pick(MainAxisSize.min, MainAxisSize.max),
          children: [
            GlyphIcon(glyph, size: 20, color: T.inkSoft),
            const SizedBox(width: 14),
            layout.pick<Widget>(
              IbashoSlider(value: value, onChanged: onChanged),
              Expanded(
                child: IbashoSlider(
                  value: value,
                  width: double.infinity,
                  onChanged: onChanged,
                ),
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(
                '${(value * 100).round()}',
                textAlign: TextAlign.right,
                style: Ty.numeral(17, color: T.inkSoft),
              ),
            ),
          ],
        );

    Future<void> setLocale(String code) => changeLanguage(ref, code);

    return ChannelScaffold(
      title: l.settingsTitle,
      glyph: Glyph.gear,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(28, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(820, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionCard(
                  title: l.settingsSound,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      SettingRow(
                        label: l.settingsMusicVolume,
                        control: volume(
                          Glyph.note,
                          preferences.musicVolume,
                          controller.setMusicVolume,
                        ),
                      ),
                      SettingRow(
                        label: l.settingsEffectsVolume,
                        divider: false,
                        control: volume(
                          Glyph.speaker,
                          preferences.effectsVolume,
                          (v) async => controller.setEffectsVolume(v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.settingsMenuMusic,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 10),
                        child: Text(l.settingsMenuMusicHint, style: Ty.caption),
                      ),
                      for (final track in library.available)
                        TrackTile(
                          title: track.id,
                          subtitle: describeTrack(l, track),
                          selected: track == currentTrack,
                          onPressed: () => ref
                              .read(musicLibraryProvider.notifier)
                              .select(track),
                          trailing: track == currentTrack
                              ? Text(l.musicPlaying,
                                  style: Ty.caption.copyWith(
                                      color: T.onAccent,
                                      fontWeight: FontWeight.w500))
                              : null,
                        ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6, top: 10),
                        child: Text(
                          l.settingsMenuMusicPending(library.pending),
                          style: Ty.micro,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.settingsPresentation,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      SettingRow(
                        label: l.settingsLanguage,
                        control: IbashoSegmented<String>(
                          options: [
                            ('es', l.settingsLanguageEs),
                            ('en', l.settingsLanguageEn),
                          ],
                          value: preferences.localeCode,
                          onChanged: setLocale,
                        ),
                      ),
                      SettingRow(
                        label: l.settingsReducedMotion,
                        hint: l.settingsReducedMotionHint,
                        divider: false,
                        control: IbashoToggle(
                          value: preferences.reducedMotion,
                          onChanged: controller.setReducedMotion,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.settingsSystem,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      SettingRow(
                        label: l.settingsCredits,
                        divider: false,
                        control: IbashoButton(
                          label: l.settingsCredits,
                          glyph: Glyph.info,
                          height: 44,
                          cue: Sfx.open,
                          onPressed: () => Navigator.of(context).push(
                            _plainRoute(const CreditsChannel(), skin.reducedMotion),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.settingsAccount,
                  padding: const EdgeInsets.fromLTRB(26, 6, 26, 6),
                  child: Column(
                    children: [
                      SettingRow(
                        label: l.settingsPassword,
                        hint: l.settingsPasswordHint,
                        control: IbashoButton(
                          label: l.settingsChangePassword,
                          glyph: Glyph.lock,
                          height: 44,
                          onPressed: () async {
                            final changed = await showChangeOwnPassword(context);
                            if (changed && context.mounted) {
                              showIbashoToast(context, l.changeOwnPasswordDone);
                            }
                          },
                        ),
                      ),
                      // La clave de respaldo se puede volver a mirar, pero
                      // solo desde un aparato que la tenga guardada en el
                      // llavero: del respaldo de la base no se saca, que es
                      // justo lo que hace que nadie mas pueda leer tus
                      // mensajes.
                      SettingRow(
                        label: l.keysShowAgain,
                        hint: keyPhrase.isEmpty ? l.keysShowUnknown : null,
                        control: IbashoButton(
                          label: l.keysShowAgain,
                          glyph: Glyph.lock,
                          height: 44,
                          onPressed: keyPhrase.isEmpty
                              ? null
                              : () => showIbashoModal<void>(
                                    context,
                                    (_) => IbashoDialog(
                                      title: l.keysTitle,
                                      body: BackupWords(words: keyPhrase),
                                      actions: [
                                        IbashoButton(
                                          label: l.actionClose,
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                        ),
                                      ],
                                    ),
                                  ),
                        ),
                      ),
                      SettingRow(
                        label: l.settingsSignOut,
                        divider: false,
                        control: IbashoButton(
                          label: l.settingsSignOut,
                          glyph: Glyph.power,
                          tone: ButtonTone.warn,
                          height: 44,
                          onPressed: () async {
                            final confirmed = await askConfirmation(
                              context,
                              title: l.signOutConfirmTitle,
                              body: l.signOutConfirmBody,
                              confirmLabel: l.signOutConfirm,
                              cancelLabel: l.actionCancel,
                              tone: ButtonTone.warn,
                            );
                            if (!confirmed || !context.mounted) return;
                            AudioService.instance.play(Sfx.back);
                            await ref.read(sessionProvider.notifier).signOut();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Center(
                  child: Text(
                    l.settingsVersion(appVersion),
                    style: Ty.micro,
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

/// Ruta interior de un canal: fundido corto, sin el gesto de apertura, que se
/// reserva para entrar desde la rejilla.
PageRoute<void> _plainRoute(Widget child, bool reducedMotion) => PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondary) => ColoredBox(
        color: T.shellTop,
        child: child,
      ),
      transitionDuration: reducedMotion
          ? T.reduced
          : const Duration(milliseconds: 260),
      reverseTransitionDuration: reducedMotion
          ? T.reduced
          : const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondary, child) => FadeTransition(
        opacity: animation,
        child: reducedMotion
            ? child
            : SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .04),
                  end: Offset.zero,
                ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              ),
      ),
    );
