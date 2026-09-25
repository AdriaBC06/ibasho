// Ibasho — canal de ajustes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/backdrops.dart';
import '../../../backend/gacha.dart';
import '../../../core/device.dart';
import '../../../core/version.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/koro.dart';
import '../../../state/providers.dart';
import '../../../theme/menu_theme.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../tama/accent_prompt.dart';
import '../../widgets/backdrop_art.dart';
import '../../widgets/controls.dart';
import '../../widgets/gacha_art.dart';
import '../../widgets/gloss.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../../layout.dart';
import '../channel_route.dart';
import '../messages/backup_key.dart';
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
    final gacha = ref.watch(gachaProvider);
    final currentTrack = MusicTrack.byId(preferences.musicTrack);
    final layout = Layout.of(context);


    /// Fila de volumen: en vertical el raíl ocupa el ancho entero.
    Widget volume(Glyph glyph, double value, ValueChanged<double> onChanged) =>
        Row(
          mainAxisSize: layout.pick(MainAxisSize.min, MainAxisSize.max),
          children: [
            GlyphIcon(glyph, size: 20, color: Ty.inkSoft),
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
                style: Ty.numeral(17, color: Ty.inkSoft),
              ),
            ),
          ],
        );

    Future<void> setLocale(String code) => changeLanguage(ref, code);

    return ChannelScaffold(
      title: l.settingsTitle,
      glyph: Glyph.gear,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          layout.pick(28, 18),
          layout.gutter,
          44,
        ),
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
                      // Desde la 0.6.2 se elige en Tamakoro, junto a las
                      // canciones propias: aqui solo se dice que suena.
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 8),
                        child: Text(
                          koroSlotOfTrack(preferences.musicTrack) != null
                              ? l.settingsMenuMusicKoro
                              : currentTrack.id,
                          style: Ty.body,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(l.settingsMenuMusicFromKoro, style: Ty.caption),
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
                        control: IbashoToggle(
                          value: preferences.reducedMotion,
                          onChanged: controller.setReducedMotion,
                        ),
                      ),
                      SettingRow(
                        label: l.settingsHourFormat,
                        divider: !Device.isDesktop,
                        control: IbashoSegmented<bool>(
                          options: [
                            (true, l.settingsHourFormat24),
                            (false, l.settingsHourFormat12),
                          ],
                          value: preferences.hourFormat24,
                          onChanged: controller.setHourFormat24,
                        ),
                      ),
                      if (Device.isDesktop)
                        SettingRow(
                          label: l.settingsFullscreen,
                          divider: false,
                          control: IbashoToggle(
                            value: preferences.fullscreen,
                            onChanged: controller.setFullscreen,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.settingsBackdrop,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 14),
                        child: Text(l.settingsBackdropHint, style: Ty.caption),
                      ),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          BackdropChip(
                            key: const ValueKey<String>('backdrop.none'),
                            id: null,
                            rarity: null,
                            label: l.backdropNone,
                            locked: false,
                            selected: preferences.backdropId.isEmpty,
                            onPressed: () => controller.setBackdrop(''),
                          ),
                          for (final b in backdrops)
                            Builder(
                              builder: (context) {
                                final owned = gacha.owns(b.key);
                                return BackdropChip(
                                  key: ValueKey<String>('backdrop.${b.id}'),
                                  id: owned ? b.id : null,
                                  rarity: b.rarity,
                                  label: owned ? l.backdropName(b.key) : '???',
                                  locked: !owned,
                                  selected: preferences.backdropId == b.id,
                                  onPressed: owned
                                      ? () async {
                                          await controller.setBackdrop(b.id);
                                          if (!context.mounted) return;
                                          await askAccentForTheme(context, ref, b.id);
                                        }
                                      : null,
                                );
                              },
                            ),
                        ],
                      ),
                      // El cristal de las pantallas del menu, solo si el tema
                      // puesto lo tiene.
                      if ((menuThemeFor(preferences.backdropId)?.surfaces.glass ?? 1) < 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                          child: SettingRow(
                            label: l.settingsGlass,
                            hint: l.settingsGlassHint,
                            divider: false,
                            control: volume(
                              Glyph.eye,
                              preferences.glassLevel / 2,
                              (v) => controller.setGlassLevel(v * 2),
                            ),
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
                            _plainRoute(
                              const CreditsChannel(),
                              skin.reducedMotion,
                            ),
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
                            final changed = await showChangeOwnPassword(
                              context,
                            );
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
                  child: Text(l.settingsVersion(appVersion), style: Ty.micro),
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
PageRoute<void> _plainRoute(Widget child, bool reducedMotion) =>
    PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondary) {
        final skin = IbashoSkin.of(context);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [skin.shellTop, skin.shellBottom],
            ),
          ),
          child: child,
        );
      },
      transitionDuration: reducedMotion
          ? T.reduced
          : const Duration(milliseconds: 260),
      reverseTransitionDuration: reducedMotion
          ? T.reduced
          : const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondary, child) =>
          FadeTransition(
            opacity: animation,
            child: reducedMotion
                ? child
                : SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0, .04),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
          ),
    );

/// Una ficha del fondo del menu: su miniatura, el nombre y la rareza. Lo que
/// no se tiene sale en silueta con «???», como los premios que se ponen a un
/// Tama (`tama_creator_screen.dart`).
/// Un fondo para elegir: la miniatura y su nombre. Bloqueado, «???».
class BackdropChip extends StatelessWidget {
  const BackdropChip({
    super.key,
    required this.id,
    required this.rarity,
    required this.label,
    required this.locked,
    required this.selected,
    required this.onPressed,
  });

  /// El `id` del fondo (sin `bg_`), o `null` si esta bloqueado o es «de
  /// serie».
  final String? id;
  final Rarity? rarity;
  final String label;
  final bool locked;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      enabled: onPressed != null,
      semanticLabel: label,
      builder: (context, state) {
        final scale = skin.reducedMotion
            ? 1.0
            : 1 + .03 * state.hover - .05 * state.press;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 92,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlossSurface(
                  radius: 16,
                  tint: selected ? skin.accent : null,
                  elevation: selected ? 2 : 1,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (id != null)
                            BackdropView(id: id)
                          else
                            const ColoredBox(color: T.wellTop),
                          if (locked)
                            const ColoredBox(color: Color(0x33324A63)),
                          if (locked)
                            Center(
                              child: Text(
                                '???',
                                style: Ty.label.copyWith(color: Ty.inkSoft),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: Ty.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (rarity != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: RarityBadge(rarity!, height: 16, faded: locked),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
