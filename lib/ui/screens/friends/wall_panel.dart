// Ibasho — muro de cumpleaños.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../audio/audio_service.dart';
import '../../../backend/models.dart';
import '../../../backend/social.dart';
import '../../../core/birthday.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/people.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../social/social_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../layout.dart';
import '../../widgets/text_field.dart';

/// El muro de cumpleaños de una cuenta, año a año.
///
/// El dia del cumpleaños (en la zona de quien cumple) sus amigos pueden dejar
/// un mensaje, uno por año. Los años anteriores se consultan con las flechas.
/// Quien cumple no escribe en su muro, pero borra lo que quiera de el.
///
/// La fecha es cosa del cliente: las reglas garantizan amigo, un mensaje por
/// año y la forma, pero no pueden saber que dia es (ver database.rules.json).
class WallPanel extends ConsumerStatefulWidget {
  const WallPanel({super.key, required this.accountId, required this.profile, required this.own});

  final String accountId;
  final UserProfile profile;

  /// Es el muro propio: se puede borrar y no se escribe.
  final bool own;

  @override
  ConsumerState<WallPanel> createState() => _WallPanelState();
}

class _WallPanelState extends ConsumerState<WallPanel> {
  static const int _columns = 2;
  static const int _rows = 2;

  /// En vertical los mensajes van en una sola columna.
  static const int _tallColumns = 1;

  final TextEditingController _text = TextEditingController();
  int? _year;
  int _page = 0;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post(int year) async {
    final l = L.of(context)!;
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    final ok = await ref.read(friendsProvider.notifier).postOnWall(widget.accountId, year, text);
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) {
      _text.clear();
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, l.wallPosted);
    } else {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.wallPostError, isError: true);
    }
  }

  Future<void> _delete(WallMessage message) async {
    final l = L.of(context)!;
    final yes = await askConfirmation(
      context,
      title: l.wallDeleteTitle,
      body: l.wallDeleteBody,
      confirmLabel: l.wallDelete,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!yes || !mounted) return;
    final ok = await ref.read(friendsProvider.notifier).deleteFromWall(message.year, message.author);
    if (!mounted) return;
    if (!ok) {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, l.wallDeleteError, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final me = ref.watch(sessionProvider.select((s) => s.accountId));
    final now = ref.watch(moodClockProvider);
    final wall = ref.watch(wallOfProvider(widget.accountId)).valueOrNull ?? const {};
    final birthday = isBirthdayToday(widget.profile, now);
    final thisYear = wallYearFor(widget.profile, now);

    final years = <int>{thisYear, ...wall.keys}.toList()..sort((a, b) => b.compareTo(a));
    final year = _year != null && years.contains(_year) ? _year! : thisYear;
    final yearIndex = years.indexOf(year);
    final messages = wall[year] ?? const <WallMessage>[];
    final mine = messages.any((m) => m.author == me);
    final canWrite = !widget.own && birthday && year == thisYear && !mine;
    final showComposer = !widget.own && year == thisYear;

    final layout = Layout.of(context);
    final tall = layout.tall;
    final columns = tall ? _tallColumns : (showComposer ? _columns : _columns + 1);
    final perPage = tall ? 2 : columns * _rows;
    final pages = math.max(1, (messages.length / perPage).ceil());
    final page = _page.clamp(0, pages - 1);
    final visible = messages.skip(page * perPage).take(perPage).toList();

    void setYear(int index) {
      AudioService.instance.play(Sfx.tick);
      setState(() {
        _year = years[index];
        _page = 0;
      });
    }

    return Padding(
      padding: tall
          ? const EdgeInsets.fromLTRB(14, 12, 14, 14)
          : const EdgeInsets.fromLTRB(28, 18, 28, 22),
      child: Column(
        children: [
          SizedBox(
            height: tall ? 48 : 40,
            child: Row(
              children: [
                GlyphIcon(Glyph.cake, size: 24, color: birthday ? T.warn : skin.accentDeep),
                const SizedBox(width: 10),
                if (!tall) ...[
                  Text(l.wallTitle, style: Ty.lead),
                  const SizedBox(width: 18),
                ],
                IconPill(
                  key: const ValueKey<String>('wall.olderYear'),
                  glyph: Glyph.arrowLeft,
                  diameter: 32,
                  onPressed: yearIndex < years.length - 1 ? () => setYear(yearIndex + 1) : null,
                ),
                SizedBox(
                  width: tall ? 56 : 70,
                  child: Text(
                    '$year',
                    textAlign: TextAlign.center,
                    style: Ty.numeral(tall ? 18 : 22, color: T.ink, weight: FontWeight.w700),
                  ),
                ),
                IconPill(
                  key: const ValueKey<String>('wall.newerYear'),
                  glyph: Glyph.arrowRight,
                  diameter: 32,
                  onPressed: yearIndex > 0 ? () => setYear(yearIndex - 1) : null,
                ),
                const Spacer(),
                if (pages > 1) ...[
                  IconPill(
                    glyph: Glyph.arrowLeft,
                    diameter: 32,
                    onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
                  ),
                  const SizedBox(width: 6),
                  Text('${page + 1} / $pages', style: Ty.numeral(16, color: T.inkSoft)),
                  const SizedBox(width: 6),
                  IconPill(
                    glyph: Glyph.arrowRight,
                    diameter: 32,
                    onPressed: page < pages - 1 ? () => setState(() => _page = page + 1) : null,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: tall ? 10 : 14),
          Expanded(
            child: _Beside(
              tall: tall,
              children: [
                if (showComposer) ...[
                  SizedBox(
                    width: tall ? double.infinity : 380,
                    child: _Composer(
                      controller: _text,
                      canWrite: canWrite,
                      alreadyWrote: mine,
                      posting: _posting,
                      birthdayLabel: _birthdayDate(context, widget.profile),
                      onPost: () => _post(thisYear),
                    ),
                  ),
                  SizedBox(width: tall ? 0 : 20, height: tall ? 12 : 0),
                ],
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Text(
                            widget.own ? l.wallEmptyOwn : l.wallEmpty,
                            textAlign: TextAlign.center,
                            style: Ty.body.copyWith(color: T.inkSoft),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, box) {
                            final cellW = (box.maxWidth - 16 * (columns - 1)) / columns;
                            // Un mensaje son 140 caracteres: la tarjeta no crece
                            // mas de lo que ocupan.
                            final cellH = math.min((box.maxHeight - 14) / (tall ? perPage : _rows), 132.0);
                            return Wrap(
                              spacing: 16,
                              runSpacing: 14,
                              children: [
                                for (final message in visible)
                                  SizedBox(
                                    width: cellW,
                                    height: cellH,
                                    child: _MessageCard(
                                      message: message,
                                      onDelete: widget.own ? () => _delete(message) : null,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _birthdayDate(BuildContext context, UserProfile profile) {
    final parts = profile.birthdayParts;
    if (parts == null) return '';
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.MMMMd(locale).format(DateTime(2000, parts.$2, parts.$3));
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.canWrite,
    required this.alreadyWrote,
    required this.posting,
    required this.birthdayLabel,
    required this.onPost,
  });

  final TextEditingController controller;
  final bool canWrite;
  final bool alreadyWrote;
  final bool posting;
  final String birthdayLabel;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    if (!canWrite) {
      return GlossSurface(
        radius: 22,
        recessed: true,
        padding: const EdgeInsets.all(22),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlyphIcon(
                alreadyWrote ? Glyph.check : Glyph.lock,
                size: 36,
                color: alreadyWrote ? skin.accentDeep : T.inkSoft,
              ),
              const SizedBox(height: 12),
              Text(
                alreadyWrote
                    ? l.wallAlreadyWrote
                    : birthdayLabel.isEmpty
                        ? l.wallNoBirthday
                        : l.wallOpensOn(birthdayLabel),
                textAlign: TextAlign.center,
                style: Ty.body.copyWith(color: T.inkSoft),
              ),
            ],
          ),
        ),
      );
    }
    final length = controller.text.trim().length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IbashoTextField(
          key: const ValueKey<String>('wall.field'),
          controller: controller,
          label: l.wallFieldLabel,
          hint: l.wallFieldHint,
          maxLength: wallMessageMax,
          multiline: true,
        ),
        Row(
          children: [
            Text(
              '$length / $wallMessageMax',
              style: Ty.numeral(14, color: length > wallMessageMax - 10 ? T.warn : T.inkSoft),
            ),
            const Spacer(),
            IbashoButton(
              key: const ValueKey<String>('wall.post'),
              label: posting ? l.changePasswordWorking : l.wallPost,
              glyph: Glyph.send,
              tone: ButtonTone.accent,
              height: 46,
              minWidth: 160,
              cue: null,
              onPressed: posting || length == 0 ? null : onPost,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l.wallOnePerYear, style: Ty.micro),
      ],
    );
  }
}

class _MessageCard extends ConsumerWidget {
  const _MessageCard({required this.message, this.onDelete});

  final WallMessage message;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final card = ref.watch(cardOfProvider(message.author)).valueOrNull;
    final accent = card?.accent ?? skin.accent;
    return GlossSurface(
      key: ValueKey<String>('wall.message.${message.year}.${message.author}'),
      radius: 20,
      elevation: 1.2,
      borderColor: Color.lerp(T.hairline, accent, .35)!,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            height: 58,
            child: GlossSurface(
              radius: 18,
              recessed: true,
              tint: accent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: OverflowBox(
                  maxWidth: 64,
                  maxHeight: 64,
                  alignment: const Alignment(0, .6),
                  child: CardTama(accountId: message.author, card: card, size: 64, joy: .9),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card?.displayName ?? '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ty.label.copyWith(color: Color.lerp(accent, T.dusk, .35)),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Text(
                    message.text,
                    overflow: TextOverflow.fade,
                    style: Ty.body.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconPill(
              key: ValueKey<String>('wall.delete.${message.author}'),
              glyph: Glyph.trash,
              diameter: 32,
              semanticLabel: l.wallDelete,
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// El escritor y los mensajes: al lado en horizontal, uno debajo del otro en
/// vertical.
class _Beside extends StatelessWidget {
  const _Beside({required this.tall, required this.children});

  final bool tall;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => tall
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)
      : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
}
