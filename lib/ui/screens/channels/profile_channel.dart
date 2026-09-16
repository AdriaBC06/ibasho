// Ibasho — canal de perfil.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../core/birthday.dart';
import '../../../backend/models.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/accent_sync.dart';
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
import '../../layout.dart';
import '../../widgets/pressable.dart';
import '../channel_route.dart';
import '../tama/tama_creator_screen.dart';
import '../friends/wall_panel.dart';
import '../tama/tama_room_screen.dart';
import 'tamas_channel.dart';

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
  bool _followsTama = false;
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
    _followsTama = profile.accentFollowsTama == true;
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
      accentFollowsTama: _followsTama,
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
    final profileTama = ref.watch(tamasProvider.select((t) => t.profileTama));

    if (profile == null) {
      return ChannelScaffold(
        title: l.profileTitle,
        glyph: Glyph.person,
        child: Center(child: Text(l.loading, style: Ty.lead)),
      );
    }
    if (!_seeded) _seed(profile);
    final layout = Layout.of(context);
    final tall = layout.tall;

    return ChannelScaffold(
      title: l.profileTitle,
      glyph: Glyph.person,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(layout.gutter, layout.pick(28, 18), layout.gutter, 44),
        child: Center(
          child: SizedBox(
            width: layout.pick(880, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Stack(
                  tall: tall,
                  gap: layout.pick(26, 22),
                  children: [
                    const _ProfileTama(),
                    _Grow(
                      tall: tall,
                      child: SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.profileUsername, style: Ty.label),
                            const SizedBox(height: 4),
                            Text(
                              profile.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tall ? Ty.title : Ty.display,
                            ),
                            SizedBox(height: tall ? 12 : 18),
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
                  // En vertical los tres campos se reparten la fila y el
                  // borrado baja debajo: en una sola linea no cabrian.
                  child: _Birthday(
                    tall: tall,
                    day: _day,
                    month: _month,
                    year: _year,
                    onClear: () => setState(() {
                      _day.clear();
                      _month.clear();
                      _year.clear();
                    }),
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
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (profileTama != null)
                            _FollowTamaChip(
                              color: accentForTama(profileTama.look.color),
                              selected: _followsTama,
                              label: l.profileAccentFollowTama,
                              onPressed: () => setState(() {
                                _followsTama = true;
                                _accent = _hex(accentForTama(profileTama.look.color));
                              }),
                            ),
                          for (final color in T.accentPalette)
                            ColorChip(
                              color: color,
                              selected: !_followsTama &&
                                  _hex(color) == _accent.toUpperCase(),
                              // Tocar un color a mano rompe la sincronizacion
                              // con el Tama.
                              onPressed: () => setState(() {
                                _followsTama = false;
                                _accent = _hex(color);
                              }),
                            ),
                        ],
                      ),
                      if (_followsTama && profileTama != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12, left: 4),
                          child: Text(l.profileAccentFollowHint, style: Ty.caption),
                        ),
                      const SizedBox(height: 22),
                      const Hairline(),
                      const SizedBox(height: 18),
                      _Stack(
                        tall: tall,
                        gap: layout.pick(26, 18),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _Grow(
                            tall: tall,
                            child: TimezoneField(
                              value: _timezone,
                              label: l.profileTimezone,
                              onChanged: (id) => setState(() => _timezone = id),
                            ),
                          ),
                          // El idioma ocupa lo que pide, como siempre: en
                          // vertical ya lo estira la columna.
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
                const SizedBox(height: 22),
                const _ProfileMusic(),
                const SizedBox(height: 26),
                // En vertical los dos botones se reparten la linea; en
                // horizontal, cada uno ocupa lo suyo y se separan.
                Builder(builder: (context) {
                  final wall = IbashoButton(
                    key: const ValueKey<String>('profile.wall'),
                    label: l.profileWall,
                    glyph: Glyph.cake,
                    height: 52,
                    cue: null,
                    onPressed: () => pushChannelPage<void>(context, (_) => const OwnWallScreen()),
                  );
                  final save = IbashoButton(
                    label: state.saving ? l.changePasswordWorking : l.actionSave,
                    tone: ButtonTone.accent,
                    glyph: Glyph.check,
                    height: 52,
                    minWidth: tall ? 0 : 200,
                    cue: null,
                    onPressed: state.saving ? null : () => _save(profile),
                  );
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: tall
                        ? [
                            Flexible(child: wall),
                            const SizedBox(width: 12),
                            Flexible(child: save),
                          ]
                        : [wall, const Spacer(), save],
                  );
                }),
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

/// La musica que oyen tus amigos al abrir tu perfil. Se guarda al tocarla,
/// como la del menu en Ajustes.
class _ProfileMusic extends ConsumerWidget {
  const _ProfileMusic();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final library = ref.watch(musicLibraryProvider);
    return SectionCard(
      title: l.profileMusic,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.profileMusicHint, style: Ty.caption),
          const SizedBox(height: 12),
          IbashoSegmented<String>(
            key: const ValueKey<String>('profile.music'),
            options: [
              ('', l.profileMusicNone),
              for (final track in library.available) (track.id, track.id),
            ],
            value: library.profileTrack ?? '',
            onChanged: (id) => ref
                .read(musicLibraryProvider.notifier)
                .selectProfileTrack(id.isEmpty ? null : MusicTrack.byId(id)),
          ),
        ],
      ),
    );
  }
}

/// Tu propio muro de cumpleaños: lo que te han dejado, año a año, con la
/// papelera en cada mensaje.
class OwnWallScreen extends ConsumerWidget {
  const OwnWallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final account = ref.watch(sessionProvider.select((s) => s.accountId));
    final now = ref.watch(moodClockProvider);
    return ChannelScaffold(
      title: l.wallOwnTitle,
      glyph: Glyph.cake,
      child: profile == null
          ? Center(child: Text(l.loading, style: Ty.lead))
          : Padding(
              padding: EdgeInsets.fromLTRB(
                Layout.of(context).gutter,
                14,
                Layout.of(context).gutter,
                16,
              ),
              child: Column(
                children: [
                  if (isBirthdayToday(profile, now))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        l.wallOwnBirthday,
                        style: Ty.title.copyWith(color: T.warn),
                      ),
                    ),
                  Expanded(
                    child: ScreenPanel(
                      child: WallPanel(accountId: account, profile: profile, own: true),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.max,
    this.width,
  });

  final TextEditingController controller;
  final String label;

  /// Sin ancho, se queda con el que le den (vertical).
  final double? width;
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

/// El Tama de perfil, vivo, con su nombre. Tocarlo abre su habitacion; si aun
/// no hay, lleva al creador.
class _ProfileTama extends ConsumerWidget {
  const _ProfileTama();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final tama = ref.watch(tamasProvider.select((t) => t.profileTama));

    void open() => pushChannelPage<void>(
          context,
          (_) => tama == null
              ? const TamaCreatorScreen()
              : TamaRoomScreen(tamaId: tama.id),
        );

    final tall = Layout.of(context).tall;
    final window = TamaWindow(
      key: const ValueKey<String>('profile.tama'),
      size: tall ? 132 : 220,
      radius: tall ? 30 : 44,
      onTap: open,
    );
    final name = Text(
      tama?.name ?? l.profileTamaEmpty,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: tall ? TextAlign.start : TextAlign.center,
      style: tama == null ? Ty.micro : Ty.lead,
    );
    final open2 = IbashoButton(
      label: tama == null ? l.tamasCreate : l.tamasTitle,
      glyph: tama == null ? Glyph.plus : Glyph.tama,
      tone: ButtonTone.quiet,
      height: 38,
      cue: null,
      onPressed: () => pushChannelPage<void>(
        context,
        (_) => tama == null ? const TamaCreatorScreen() : const TamasChannel(),
      ),
    );

    // En vertical el Tama no se lleva media pantalla: se pone a un lado, con
    // su nombre y el acceso al canal al otro.
    if (tall) {
      return Row(
        children: [
          window,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                name,
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(fit: BoxFit.scaleDown, child: open2),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: 220,
      child: Column(
        children: [
          window,
          const SizedBox(height: 12),
          name,
          const SizedBox(height: 8),
          open2,
        ],
      ),
    );
  }
}

/// Muestra de acento que sigue al Tama: su color con la silueta encima.
class _FollowTamaChip extends StatelessWidget {
  const _FollowTamaChip({
    required this.color,
    required this.selected,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Pressable(
        key: const ValueKey<String>('profile.followTama'),
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, state) => FocusRing(
          visible: state.focus,
          radius: 19,
          child: Transform.translate(
            offset: Offset(0, -2 * state.hover + 1.5 * state.press),
            child: SizedBox(
              height: 38,
              child: GlossSurface(
                radius: 19,
                tint: color,
                elevation: selected ? 1.6 : .8,
                borderWidth: selected ? 2.5 : 1,
                borderColor: selected ? Color.lerp(color, T.dusk, .45)! : T.hairline,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlyphIcon(
                      selected ? Glyph.check : Glyph.tama,
                      size: 20,
                      color: T.onAccent,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Ty.body.copyWith(color: T.onAccent, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

/// Dos bloques uno al lado del otro en horizontal y uno encima del otro en
/// vertical. Es el reordenamiento que hacen casi todas las pantallas.
class _Stack extends StatelessWidget {
  const _Stack({
    required this.tall,
    required this.children,
    this.gap = 18,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final bool tall;
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final spaced = <Widget>[
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(width: tall ? 0 : gap, height: tall ? gap : 0),
        children[i],
      ],
    ];
    return tall
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: spaced)
        : Row(crossAxisAlignment: crossAxisAlignment, children: spaced);
  }
}

/// Ocupa lo que sobra en horizontal; en vertical ya estira la columna.
class _Grow extends StatelessWidget {
  const _Grow({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) => tall ? child : Expanded(child: child);
}

/// La fecha de cumpleaños: la tarta, los tres campos y el boton de quitarla.
class _Birthday extends StatelessWidget {
  const _Birthday({
    required this.tall,
    required this.day,
    required this.month,
    required this.year,
    required this.onClear,
  });

  final bool tall;
  final TextEditingController day;
  final TextEditingController month;
  final TextEditingController year;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final clear = IbashoButton(
      label: l.profileClearBirthday,
      tone: ButtonTone.quiet,
      height: 44,
      onPressed: onClear,
    );

    if (!tall) {
      return Row(
        children: [
          const GlyphIcon(Glyph.cake, size: 24, color: T.warn),
          const SizedBox(width: 18),
          _NumberField(controller: day, label: l.profileDay, width: 96, max: 2),
          const SizedBox(width: 12),
          _NumberField(controller: month, label: l.profileMonth, width: 96, max: 2),
          const SizedBox(width: 12),
          _NumberField(controller: year, label: l.profileYear, width: 124, max: 4),
          const SizedBox(width: 16),
          clear,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 30),
              child: GlyphIcon(Glyph.cake, size: 24, color: T.warn),
            ),
            const SizedBox(width: 12),
            Expanded(child: _NumberField(controller: day, label: l.profileDay, max: 2)),
            const SizedBox(width: 10),
            Expanded(child: _NumberField(controller: month, label: l.profileMonth, max: 2)),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _NumberField(controller: year, label: l.profileYear, max: 4),
            ),
          ],
        ),
        Align(alignment: Alignment.centerRight, child: clear),
      ],
    );
  }
}
