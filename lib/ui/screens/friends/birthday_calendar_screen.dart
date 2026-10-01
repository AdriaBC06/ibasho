// Ibasho — el calendario de cumpleaños de los amigos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/tama.dart';
import '../../../core/birthday.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../social/social_widgets.dart';
import '../../tama/tama_view.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/panel.dart';
import '../../widgets/pressable.dart';
import '../../layout.dart';
import '../channel_route.dart';
import 'friend_profile_screen.dart';

/// Los cumpleaños de todos: arriba (o a la izquierda) el mes con el Tama de
/// perfil de quien cumple cada dia, y al lado los proximos por orden. El
/// propio tambien sale.
///
/// Las fechas son las del calendario de quien mira; el gorro de fiesta de la
/// lista de amigos sigue la zona de cada uno.
class BirthdayCalendarScreen extends ConsumerStatefulWidget {
  const BirthdayCalendarScreen({super.key});

  @override
  ConsumerState<BirthdayCalendarScreen> createState() => _BirthdayCalendarScreenState();
}

class _BirthdayCalendarScreenState extends ConsumerState<BirthdayCalendarScreen> {
  late DateTime _month = () {
    final now = ref.read(moodClockProvider);
    return DateTime(now.year, now.month);
  }();

  /// Dia elegido en el mes que se ve; `null` enseña los proximos.
  int? _selected;

  void _shift(int months) {
    AudioService.instance.play(Sfx.tick);
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
      _selected = null;
    });
  }

  void _select(int day) => setState(() => _selected = _selected == day ? null : day);

  void _open(BirthdayEntry entry) {
    final account = entry.accountId;
    if (account == null) return;
    pushChannelPage<void>(context, (_) => FriendProfileScreen(accountId: account));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.arrowLeft) {
      _shift(-1);
    } else if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.arrowRight) {
      _shift(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final now = ref.watch(moodClockProvider);
    final entries = _entries();
    final byDay = birthdaysByDay(entries, _month.year, _month.month);

    final month = PageSwipe(
      onPrevious: () => _shift(-1),
      onNext: () => _shift(1),
      child: ScreenPanel(
        child: _MonthView(
          month: _month,
          today: now,
          byDay: byDay,
          selected: _selected,
          onShift: _shift,
          onSelect: _select,
        ),
      ),
    );

    final selected = _selected;
    final list = ScreenPanel(
      child: _BirthdayList(
        entries: selected == null ? upcomingBirthdays(entries, now) : (byDay[selected] ?? const []),
        today: now,
        day: selected == null ? null : DateTime(_month.year, _month.month, selected),
        hasOwn: entries.any((e) => e.mine),
        onOpen: _open,
        onBack: () => setState(() => _selected = null),
      ),
    );

    return ChannelScaffold(
      title: l.friendsBirthdays,
      glyph: Glyph.calendar,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Padding(
          padding: EdgeInsets.fromLTRB(layout.gutter, 14, layout.gutter, 16),
          child: LayoutBuilder(builder: (context, box) {
            if (!layout.tall) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: month),
                  SizedBox(width: layout.gap),
                  Expanded(flex: 2, child: list),
                ],
              );
            }
            // En vertical el mes se lleva lo que pide su rejilla y la lista
            // el resto, con un minimo para que se vean dos o tres.
            final rows = _MonthView.rowsFor(_month, _firstWeekday(context));
            final cell = (box.maxWidth - 24) / 7;
            final want = _MonthView.chrome + rows * math.min(cell, 54.0);
            return Column(
              children: [
                SizedBox(height: math.min(want, box.maxHeight - 180), child: month),
                SizedBox(height: layout.gap * .75),
                Expanded(child: list),
              ],
            );
          }),
        ),
      ),
    );
  }

  List<BirthdayEntry> _entries() {
    final friends = ref.watch(friendsProvider.select((s) => s.friends));
    final mine = ref.watch(profileProvider.select((p) => p.profile));
    final username = ref.watch(sessionProvider.select((s) => s.username));
    return [
      ?BirthdayEntry.of(null, _nameOf(mine?.displayName, username), mine),
      for (final f in friends)
        if (ref.watch(friendProfileProvider(f.accountId)).valueOrNull case final profile?)
          ?BirthdayEntry.of(f.accountId, _nameOf(profile.displayName, profile.username), profile),
    ];
  }

  static String _nameOf(String? display, String username) =>
      display != null && display.trim().isNotEmpty ? display : username;
}

/// Lunes primero en castellano; domingo en ingles.
int _firstWeekday(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'en' ? DateTime.sunday : DateTime.monday;

/// La hoja del mes: cabecera con flechas, los dias de la semana y la
/// rejilla. Cada dia con cumpleaños lleva el Tama de quien cumple.
class _MonthView extends ConsumerWidget {
  const _MonthView({
    required this.month,
    required this.today,
    required this.byDay,
    required this.selected,
    required this.onShift,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final Map<int, List<BirthdayEntry>> byDay;
  final int? selected;
  final ValueChanged<int> onShift;
  final ValueChanged<int> onSelect;

  /// Alto de todo lo que no es rejilla: cabecera, dias de la semana y
  /// margenes.
  static const double chrome = 12 + 48 + 6 + 20 + 6 + 12;

  static int _lead(DateTime month, int firstWeekday) => (month.weekday - firstWeekday) % 7;

  static int rowsFor(DateTime month, int firstWeekday) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    return ((_lead(month, firstWeekday) + days) / 7).ceil();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final first = _firstWeekday(context);
    final lead = _lead(month, first);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final rows = rowsFor(month, first);
    final title = DateFormat.yMMMM(locale).format(month);
    final names = DateFormat('EEEEE', locale);
    // Un lunes cualquiera (el 5 de enero de 1970) para sacar las iniciales.
    final weekdays = [for (var i = 0; i < 7; i++) names.format(DateTime(1970, 1, 4 + first + i))];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconPill(
                  key: const ValueKey<String>('birthdays.prev'),
                  glyph: Glyph.arrowLeft,
                  diameter: 44,
                  cue: null,
                  semanticLabel: l.birthdaysPrevMonth,
                  onPressed: () => onShift(-1),
                ),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey<String>('birthdays.month'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.lead.copyWith(color: skin.accentDeep),
                  ),
                ),
                IconPill(
                  key: const ValueKey<String>('birthdays.next'),
                  glyph: Glyph.arrowRight,
                  diameter: 44,
                  cue: null,
                  semanticLabel: l.birthdaysNextMonth,
                  onPressed: () => onShift(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 20,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  for (final w in weekdays)
                    Expanded(child: Text(w, textAlign: TextAlign.center, style: Ty.micro)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth / 7;
              final h = box.maxHeight / rows;
              return Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (var r = 0; r < rows; r++)
                    SizedBox(
                      height: h,
                      child: Row(
                        children: [
                          for (var c = 0; c < 7; c++)
                            SizedBox(
                              width: w,
                              child: () {
                                final day = r * 7 + c - lead + 1;
                                if (day < 1 || day > days) return const SizedBox.shrink();
                                return _DayCell(
                                  day: day,
                                  date: DateTime(month.year, month.month, day),
                                  people: byDay[day] ?? const [],
                                  today: today.year == month.year && today.month == month.month && today.day == day,
                                  selected: selected == day,
                                  onPressed: () => onSelect(day),
                                );
                              }(),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.people,
    required this.today,
    required this.selected,
    required this.onPressed,
  });

  final int day;
  final DateTime date;
  final List<BirthdayEntry> people;
  final bool today;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final has = people.isNotEmpty;
    final label = [
      DateFormat.MMMMd(locale).format(date),
      for (final p in people) p.name,
    ].join(', ');

    return Pressable(
      key: ValueKey<String>('birthdays.day.$day'),
      onPressed: has ? onPressed : null,
      enabled: has,
      cursor: has ? SystemMouseCursors.click : MouseCursor.defer,
      semanticLabel: label,
      builder: (context, state) => LayoutBuilder(builder: (context, box) {
        final side = math.min(box.maxWidth, box.maxHeight);
        return Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(math.min(14, side * .26)),
              color: selected
                  ? skin.accent.withValues(alpha: .28)
                  : has
                      ? Color.lerp(T.shellTop, skin.accent, .12 + state.hover * .08)
                      : null,
              border: today
                  ? Border.all(color: skin.accentDeep, width: 2)
                  : has
                      ? Border.all(color: skin.accent.withValues(alpha: .35))
                      : null,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (has)
                  Positioned.fill(
                    child: Align(
                      // En casillas pequeñas el Tama baja y encoge para no
                      // tapar el numero.
                      alignment: Alignment(side < 60 ? .3 : 0, side < 60 ? 1 : .55),
                      child: IgnorePointer(
                        child: _PersonTama(entry: people.first, size: side * (side < 60 ? .68 : .82)),
                      ),
                    ),
                  ),
                Positioned(
                  left: 5,
                  top: 3,
                  child: Text(
                    '$day',
                    style: Ty.numeral(
                      side < 44 ? 11 : 13,
                      color: today ? skin.accentDeep : (has ? Ty.ink : Ty.inkSoft),
                      weight: today || has ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (people.length > 1)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: skin.accentDeep, borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        child: Text('+${people.length - 1}',
                            style: Ty.numeral(10, color: T.onAccent, weight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// El Tama de perfil de quien cumple: el de un amigo o el propio.
class _PersonTama extends ConsumerWidget {
  const _PersonTama({required this.entry, required this.size});

  final BirthdayEntry entry;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = entry.accountId;
    if (account != null) return CardTama(accountId: account, size: size);
    final tama = ref.watch(tamasProvider.select((t) => t.profileTama));
    if (tama == null) {
      return SizedBox.square(
        dimension: size,
        child: Center(child: GlyphIcon(Glyph.tama, size: size * .5, color: Ty.inkSoft, strokeWidth: 2.2)),
      );
    }
    return TamaView(
      look: tama.look,
      personality: tama.personality,
      name: tama.name,
      voice: tama.voice,
      seed: tama.id.hashCode ^ size.round(),
      joy: .5,
      size: size,
      interactive: false,
      shadow: false,
      wear: TamaWear.none,
    );
  }
}

/// Los proximos cumpleaños, o los del dia elegido.
class _BirthdayList extends ConsumerWidget {
  const _BirthdayList({
    required this.entries,
    required this.today,
    required this.day,
    required this.hasOwn,
    required this.onOpen,
    required this.onBack,
  });

  final List<BirthdayEntry> entries;
  final DateTime today;

  /// El dia elegido, o `null` para los proximos.
  final DateTime? day;
  final bool hasOwn;
  final ValueChanged<BirthdayEntry> onOpen;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final day = this.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const GlyphIcon(Glyph.cake, size: 20, color: T.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    day == null ? l.birthdaysUpcoming : DateFormat.MMMMd(locale).format(day),
                    key: const ValueKey<String>('birthdays.listTitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ty.label.copyWith(color: skin.accentDeep, fontWeight: FontWeight.w600),
                  ),
                ),
                if (day != null)
                  IbashoButton(
                    key: const ValueKey<String>('birthdays.showUpcoming'),
                    label: l.birthdaysShowUpcoming,
                    tone: ButtonTone.quiet,
                    height: 36,
                    cue: Sfx.back,
                    onPressed: onBack,
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      day == null ? l.birthdaysEmpty : l.birthdaysNoneThatDay,
                      textAlign: TextAlign.center,
                      style: Ty.caption,
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey<String>('birthdays.list'),
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: entries.length,
                  itemBuilder: (context, i) => _BirthdayRow(
                    entry: entries[i],
                    today: today,
                    onPressed: entries[i].mine ? null : () => onOpen(entries[i]),
                  ),
                ),
        ),
        if (!hasOwn && day == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Text(
              l.birthdaysSetYours,
              key: const ValueKey<String>('birthdays.setYours'),
              textAlign: TextAlign.center,
              style: Ty.micro,
            ),
          ),
      ],
    );
  }
}

class _BirthdayRow extends ConsumerWidget {
  const _BirthdayRow({required this.entry, required this.today, required this.onPressed});

  final BirthdayEntry entry;
  final DateTime today;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final locale = ref.watch(localeProvider).languageCode;
    final days = entry.daysFrom(today);
    final turns = entry.turnsFrom(today);
    final when = switch (days) {
      0 => l.birthdaysToday,
      1 => l.birthdaysTomorrow,
      _ => l.birthdaysInDays(days),
    };
    final date = DateFormat.MMMMd(locale).format(entry.nextFrom(today));
    final detail = [
      date,
      if (turns != null) entry.mine ? l.birthdaysTurnsYou(turns) : l.birthdaysTurns(turns),
    ].join(' · ');

    return Pressable(
      key: ValueKey<String>('birthdays.row.${entry.accountId ?? 'me'}'),
      onPressed: onPressed,
      cue: onPressed == null ? null : Sfx.tick,
      cursor: onPressed == null ? MouseCursor.defer : SystemMouseCursors.click,
      semanticLabel: '${entry.mine ? l.birthdaysYou : entry.name}, $detail, $when',
      builder: (context, state) => Container(
        height: 64,
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: days == 0
              ? skin.accent.withValues(alpha: .18)
              : skin.accent.withValues(alpha: .04 + state.hover * .08),
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 56,
              child: IgnorePointer(
                child: OverflowBox(
                  maxWidth: 64,
                  maxHeight: 64,
                  child: _PersonTama(entry: entry, size: 60),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Ty.body.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (entry.mine) ...[
                        const SizedBox(width: 6),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: skin.accent.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            child: Text(l.birthdaysYou, style: Ty.micro.copyWith(color: skin.accentDeep)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ty.caption),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              when,
              style: Ty.caption.copyWith(
                color: days <= 1 ? skin.accentDeep : Ty.inkSoft,
                fontWeight: days <= 1 ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
