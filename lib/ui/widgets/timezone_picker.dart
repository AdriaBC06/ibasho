// Ibasho — selector de zona horaria.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../core/timezones.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import 'controls.dart';
import 'glyphs.dart';
import 'gloss.dart';
import 'overlays.dart';
import 'pressable.dart';
import 'text_field.dart';

/// Campo que ensena la zona elegida y abre el selector al pulsarlo.
class TimezoneField extends StatelessWidget {
  const TimezoneField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final zone = zoneById(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(label, style: Ty.label),
        ),
        Pressable(
          onPressed: () async {
            final picked = await showTimezonePicker(context, value);
            if (picked != null) onChanged(picked);
          },
          builder: (context, state) => FocusRing(
            visible: state.focus,
            radius: T.fieldRadius,
            child: GlossSurface(
              radius: T.fieldRadius,
              recessed: true,
              borderColor: Color.lerp(T.hairline, skin.accentDeep, state.hover)!,
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              child: Row(
                children: [
                  Text(
                    zone?.offsetLabel ?? '',
                    style: Ty.numeral(15, color: skin.accentDeep),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      zone?.city ?? value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Ty.body.copyWith(fontSize: 17, height: 1.3),
                    ),
                  ),
                  const GlyphIcon(Glyph.chevronDown, size: 20, color: T.inkSoft),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }
}

Future<String?> showTimezonePicker(BuildContext context, String current) =>
    showIbashoModal<String>(context, (_) => _TimezonePicker(current: current));

class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({required this.current});

  final String current;

  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<_TimezonePicker> {
  static const double _rowHeight = 48;

  final TextEditingController _query = TextEditingController();
  late final List<ZoneEntry> _all = allZones();
  late List<ZoneEntry> _visible = _all;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _initialOffset(),
  );

  double _initialOffset() {
    final index = _all.indexWhere((z) => z.id == widget.current);
    return index <= 3 ? 0 : (index - 3) * _rowHeight;
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String text) {
    setState(() => _visible = _all.where((z) => matchesZone(z, text)).toList());
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);

    return IbashoDialog(
      title: l.profileTimezone,
      width: 640,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IbashoTextField(
            controller: _query,
            label: l.timezoneSearch,
            hint: l.timezoneSearchHint,
            autofocus: true,
            maxLength: 40,
            onChanged: _filter,
            onSubmitted: (_) {
              if (_visible.isNotEmpty) Navigator.of(context).pop(_visible.first.id);
            },
          ),
          SizedBox(
            height: _rowHeight * 7,
            child: GlossSurface(
              radius: 18,
              recessed: true,
              padding: const EdgeInsets.all(6),
              child: _visible.isEmpty
                  ? Center(child: Text(l.timezoneNone, style: Ty.caption))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: ScrollConfiguration(
                        behavior: const ScrollBehavior().copyWith(scrollbars: false, overscroll: false),
                        child: RawScrollbar(
                          controller: _scroll,
                          thumbColor: skin.accent.withValues(alpha: .75),
                          radius: const Radius.circular(5),
                          thickness: 6,
                          child: ListView.builder(
                            controller: _scroll,
                            itemExtent: _rowHeight,
                            itemCount: _visible.length,
                            itemBuilder: (context, i) => _ZoneRow(
                              zone: _visible[i],
                              selected: _visible[i].id == widget.current,
                              newOffset: i == 0 ||
                                  _visible[i - 1].offset != _visible[i].offset,
                              onPressed: () =>
                                  Navigator.of(context).pop(_visible[i].id),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      actions: [
        IbashoButton(
          label: l.actionCancel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ZoneRow extends StatelessWidget {
  const _ZoneRow({
    required this.zone,
    required this.selected,
    required this.newOffset,
    required this.onPressed,
  });

  final ZoneEntry zone;
  final bool selected;

  /// Primera fila de su desplazamiento: se le marca el UTC con mas peso para
  /// que la lista se lea por bloques.
  final bool newOffset;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Pressable(
      onPressed: onPressed,
      builder: (context, state) {
        final Widget row = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              SizedBox(
                width: 104,
                child: Text(
                  zone.offsetLabel,
                  style: Ty.numeral(
                    14,
                    color: selected
                        ? T.onAccent
                        : newOffset
                            ? skin.accentDeep
                            : T.inkSoft.withValues(alpha: .55),
                    weight: newOffset || selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  zone.city,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.body.copyWith(
                    color: selected ? T.onAccent : T.ink,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              Text(
                zone.region,
                style: Ty.micro.copyWith(
                  color: selected ? T.onAccent : T.inkSoft,
                ),
              ),
            ],
          ),
        );
        if (selected) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: GlossSurface(
              radius: 12,
              tint: skin.accent,
              elevation: .6,
              borderColor: skin.accentDeep,
              child: row,
            ),
          );
        }
        return ColoredBox(
          color: skin.accentWash.withValues(alpha: state.hover * .9),
          child: row,
        );
      },
    );
  }
}
