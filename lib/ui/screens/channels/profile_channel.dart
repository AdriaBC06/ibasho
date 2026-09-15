// Ibasho — canal de perfil.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/profile.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';
import '../../widgets/timezone_picker.dart';
import '../channel_route.dart';

class ProfileChannel extends ConsumerStatefulWidget {
  const ProfileChannel({super.key});

  @override
  ConsumerState<ProfileChannel> createState() => _ProfileChannelState();
}

class _ProfileChannelState extends ConsumerState<ProfileChannel> {
  final TextEditingController _displayName = TextEditingController();
  final TextEditingController _status = TextEditingController();
  final TextEditingController _day = TextEditingController();
  final TextEditingController _month = TextEditingController();
  final TextEditingController _year = TextEditingController();

  String _timezone = '';
  String _accent = '';
  String _locale = 'es';
  bool _seeded = false;
  String? _nameError;

  @override
  void dispose() {
    _displayName.dispose();
    _status.dispose();
    _day.dispose();
    _month.dispose();
    _year.dispose();
    super.dispose();
  }

  void _seed(UserProfile profile) {
    _displayName.text = profile.displayName;
    _status.text = profile.statusMessage;
    _timezone =
        profile.timezone.isEmpty ? localTimezoneName() : profile.timezone;
    final parts = profile.birthdayParts;
    _day.text = parts == null ? '' : parts.$3.toString().padLeft(2, '0');
    _month.text = parts == null ? '' : parts.$2.toString().padLeft(2, '0');
    _year.text = parts == null ? '' : parts.$1.toString();
    _accent = profile.accentColor;
    _locale = profile.locale;
    _seeded = true;
  }

  String _birthdayValue() {
    final day = int.tryParse(_day.text);
    final month = int.tryParse(_month.text);
    final year = int.tryParse(_year.text);
    if (day == null || month == null || year == null) return '';
    if (day < 1 || day > 31 || month < 1 || month > 12) return '';
    if (year < 1900 || year > DateTime.now().year) return '';
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }

  Future<void> _save(UserProfile current) async {
    final l = L.of(context)!;
    final name = _displayName.text.trim();
    if (name.isEmpty || name.length > 24) {
      AudioService.instance.play(Sfx.error);
      setState(() => _nameError = l.profileErrorDisplayName);
      return;
    }
    setState(() => _nameError = null);

    final next = current.copyWith(
      displayName: name,
      statusMessage: _status.text.trim(),
      birthday: _birthdayValue(),
      timezone: _timezone,
      locale: _locale,
      accentColor: _accent,
    );

    final saved = await ref.read(profileProvider.notifier).save(next);
    if (!mounted) return;
    if (saved) {
      // El idioma del perfil manda sobre el local en cuanto se guarda.
      await ref.read(preferencesProvider.notifier).setLocale(_locale);
      if (!mounted) return;
      AudioService.instance.play(Sfx.open);
      showIbashoToast(context, l.profileSaved);
    } else {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.profileSaveError, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final state = ref.watch(profileProvider);
    final profile = state.profile;

    if (profile == null) {
      return ChannelScaffold(
        title: l.profileTitle,
        glyph: Glyph.person,
        child: Center(child: Text(l.loading, style: Ty.lead)),
      );
    }
    if (!_seeded) _seed(profile);

    return ChannelScaffold(
      title: l.profileTitle,
      glyph: Glyph.person,
      child: IbashoScroll(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 44),
        child: Center(
          child: SizedBox(
            width: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TamaReservation(label: l.profileTamaSlot),
                    const SizedBox(width: 26),
                    Expanded(
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.profileUsername, style: Ty.label),
                            const SizedBox(height: 4),
                            Text(profile.username, style: Ty.display),
                            const SizedBox(height: 18),
                            IbashoTextField(
                              controller: _displayName,
                              label: l.profileDisplayName,
                              maxLength: 24,
                              error: _nameError,
                            ),
                            IbashoTextField(
                              controller: _status,
                              label: l.profileStatusMessage,
                              hint: l.profileStatusHint,
                              maxLength: 100,
                              multiline: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.profileBirthday,
                  child: Row(
                    children: [
                      const GlyphIcon(Glyph.cake, size: 24, color: T.warn),
                      const SizedBox(width: 18),
                      _NumberField(controller: _day, label: l.profileDay, width: 96, max: 2),
                      const SizedBox(width: 12),
                      _NumberField(controller: _month, label: l.profileMonth, width: 96, max: 2),
                      const SizedBox(width: 12),
                      _NumberField(controller: _year, label: l.profileYear, width: 124, max: 4),
                      const SizedBox(width: 16),
                      IbashoButton(
                        label: l.profileClearBirthday,
                        tone: ButtonTone.quiet,
                        height: 44,
                        onPressed: () => setState(() {
                          _day.clear();
                          _month.clear();
                          _year.clear();
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: l.profileAccent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          for (final color in T.accentPalette)
                            ColorChip(
                              color: color,
                              selected: _hex(color) == _accent.toUpperCase(),
                              onPressed: () =>
                                  setState(() => _accent = _hex(color)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Hairline(),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TimezoneField(
                              value: _timezone,
                              label: l.profileTimezone,
                              onChanged: (id) => setState(() => _timezone = id),
                            ),
                          ),
                          const SizedBox(width: 26),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 6, bottom: 6),
                                child: Text(l.profileLocale, style: Ty.label),
                              ),
                              IbashoSegmented<String>(
                                options: [
                                  ('es', l.settingsLanguageEs),
                                  ('en', l.settingsLanguageEn),
                                ],
                                value: _locale,
                                onChanged: (v) => setState(() => _locale = v),
                              ),
                              const SizedBox(height: 22),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IbashoButton(
                      label: state.saving ? l.changePasswordWorking : l.actionSave,
                      tone: ButtonTone.accent,
                      glyph: Glyph.check,
                      height: 52,
                      minWidth: 200,
                      cue: null,
                      onPressed: state.saving ? null : () => _save(profile),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    _accentName(skin.accent),
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

  static String _hex(Color color) =>
      '#${((color.r * 255).round() << 16 | (color.g * 255).round() << 8 | (color.b * 255).round()).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static String _accentName(Color color) => _hex(color);
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.width,
    required this.max,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final int max;

  @override
  Widget build(BuildContext context) => IbashoTextField(
        controller: controller,
        label: label,
        width: width,
        maxLength: max,
        formatters: [FilteringTextInputFormatter.digitsOnly],
      );
}

/// El hueco del Tama dentro del perfil. No hace nada todavia: es el sitio
/// reservado para el creador del CP2.
class _TamaReservation extends StatelessWidget {
  const _TamaReservation({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return SizedBox(
      width: 220,
      child: Column(
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: GlossSurface(
              radius: 44,
              recessed: true,
              child: Center(
                child: GlyphIcon(
                  Glyph.tama,
                  size: 104,
                  color: skin.accent.withValues(alpha: .5),
                  strokeWidth: 2.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center, style: Ty.micro),
        ],
      ),
    );
  }
}
