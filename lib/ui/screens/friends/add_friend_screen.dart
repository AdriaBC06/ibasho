// Ibasho — añadir amigo por codigo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../core/friend_code.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/friends.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../social/friend_code_input.dart';
import '../../social/social_widgets.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';
import '../../layout.dart';
import '../channel_route.dart';
import '../channels/friends_channel.dart';
import 'friend_profile_screen.dart';

/// Lo que dice el campo mientras se escribe.
enum _Entry { typing, invalid, searching, done }

/// Buscar a alguien por su codigo y mandarle una solicitud.
///
/// Arriba, el campo: pone los guiones solo, acepta pegar el codigo con o sin
/// ellos y comprueba el digito de control en cuanto hay doce, sin tocar la
/// red. Abajo, la ficha reducida de quien tiene ese codigo: nombre, Tama y
/// color, y nada mas.
class AddFriendScreen extends ConsumerStatefulWidget {
  const AddFriendScreen({super.key});

  @override
  ConsumerState<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends ConsumerState<AddFriendScreen> {
  final TextEditingController _code = TextEditingController();
  _Entry _entry = _Entry.typing;
  FriendLookup? _result;
  int _generation = 0;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onChanged);
  }

  @override
  void dispose() {
    _code.removeListener(_onChanged);
    _code.dispose();
    super.dispose();
  }

  String get _digits => FriendCode.normalize(_code.text) ?? '';

  void _onChanged() {
    final digits = _digits;
    final generation = ++_generation;
    if (digits.length < FriendCode.length) {
      if (_entry != _Entry.typing || _result != null) {
        setState(() {
          _entry = _Entry.typing;
          _result = null;
        });
      }
      return;
    }
    // Doce digitos: primero el control, en local. Un codigo mal tecleado no
    // llega a la red.
    if (!FriendCode.isValid(digits)) {
      AudioService.instance.play(Sfx.error);
      setState(() {
        _entry = _Entry.invalid;
        _result = null;
      });
      return;
    }
    setState(() {
      _entry = _Entry.searching;
      _result = null;
    });
    unawaited(ref.read(friendsProvider.notifier).lookup(digits).then((result) {
      if (!mounted || generation != _generation) return;
      AudioService.instance.play(result.outcome == LookupOutcome.found ? Sfx.open : Sfx.error);
      setState(() {
        _entry = _Entry.done;
        _result = result;
      });
    }));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || !mounted) return;
    final formatted = const FriendCodeFormatter().formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
    );
    _code.value = formatted;
  }

  Future<void> _send(FriendLookup result) async {
    final account = result.accountId;
    if (account == null || _sending) return;
    final l = L.of(context)!;
    setState(() => _sending = true);
    final controller = ref.read(friendsProvider.notifier);
    final becameFriends = result.relation == FriendRelation.requestedYou;
    final failure = await controller.sendRequest(account);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (failure == null) {
        _result = FriendLookup(
          LookupOutcome.found,
          accountId: account,
          card: result.card,
          relation: controller.relationWith(account) == FriendRelation.none
              ? (becameFriends ? FriendRelation.friend : FriendRelation.requested)
              : controller.relationWith(account),
        );
      }
    });
    if (failure == null) {
      AudioService.instance.play(Sfx.chime);
      showIbashoToast(context, becameFriends ? l.friendsAccepted : l.addFriendSent);
    } else {
      AudioService.instance.play(Sfx.error);
      showIbashoToast(context, friendFailureText(l, failure), isError: true);
    }
  }

  String? get _fieldError {
    final l = L.of(context)!;
    if (_entry == _Entry.invalid) return l.addFriendInvalid;
    return switch (_result?.outcome) {
      LookupOutcome.notFound => l.addFriendNotFound,
      LookupOutcome.self => l.addFriendSelf,
      LookupOutcome.network => l.loginErrorNetwork,
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final digits = _digits.length;
    final error = _fieldError;
    final layout = Layout.of(context);

    return ChannelScaffold(
      title: l.addFriendTitle,
      glyph: Glyph.personPlus,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: Column(
          children: [
            const SizedBox(height: 14),
            SizedBox(
              height: layout.pick(250, 214),
              child: ScreenPanel(
                child: Center(
                  child: SingleChildScrollView(
                  child: SizedBox(
                    width: layout.pick(620, layout.width - layout.gutter * 2 - 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.addFriendLead,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: layout.pick(Ty.title, Ty.lead),
                        ),
                        SizedBox(height: layout.pick(18, 12)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: IbashoTextField(
                                key: const ValueKey<String>('addFriend.field'),
                                controller: _code,
                                label: l.addFriendField,
                                hint: '0000-0000-0000',
                                autofocus: true,
                                error: error,
                                textStyle: Ty.numeral(layout.pick(32, 24), weight: FontWeight.w700)
                                    .copyWith(letterSpacing: layout.pick(2, 1), height: 1.2),
                                formatters: const [FriendCodeFormatter()],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Padding(
                              padding: EdgeInsets.only(top: layout.pick(30, 26)),
                              child: IconPill(
                                key: const ValueKey<String>('addFriend.paste'),
                                glyph: Glyph.paste,
                                diameter: layout.pick(52, 48),
                                semanticLabel: l.addFriendPaste,
                                onPressed: _paste,
                              ),
                            ),
                          ],
                        ),
                        if (error == null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              _entry == _Entry.searching
                                  ? l.addFriendSearching
                                  : l.addFriendDigits(digits, FriendCode.length),
                              style: Ty.caption.copyWith(
                                color: digits == FriendCode.length ? skin.accentDeep : T.inkSoft,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ScreenPanel(
                child: _Result(
                  result: _result,
                  sending: _sending,
                  onSend: _send,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.result, required this.sending, required this.onSend});

  final FriendLookup? result;
  final bool sending;
  final ValueChanged<FriendLookup> onSend;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final found = result;
    if (found == null || found.outcome != LookupOutcome.found) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 150,
              child: GlossSurface(
                radius: 42,
                recessed: true,
                child: Center(
                  child: GlyphIcon(
                    Glyph.friends,
                    size: 72,
                    color: skin.accent.withValues(alpha: .55),
                    strokeWidth: 2.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(l.addFriendEmpty, style: Ty.body.copyWith(color: T.inkSoft)),
          ],
        ),
      );
    }

    final card = found.card;
    final accent = card?.accent ?? T.inkSoft;
    final name = card?.displayName ?? l.addFriendNoCard;

    final Widget action = switch (found.relation) {
      FriendRelation.none => IbashoButton(
          key: const ValueKey<String>('addFriend.send'),
          label: sending ? l.changePasswordWorking : l.addFriendSend,
          glyph: Glyph.send,
          tone: ButtonTone.accent,
          height: 52,
          minWidth: 240,
          cue: null,
          onPressed: sending ? null : () => onSend(found),
        ),
      FriendRelation.requestedYou => IbashoButton(
          key: const ValueKey<String>('addFriend.send'),
          label: sending ? l.changePasswordWorking : l.addFriendAcceptTheirs,
          glyph: Glyph.check,
          tone: ButtonTone.accent,
          height: 52,
          minWidth: 240,
          cue: null,
          onPressed: sending ? null : () => onSend(found),
        ),
      FriendRelation.requested => IbashoButton(
          key: const ValueKey<String>('addFriend.sent'),
          label: l.addFriendAlreadySent,
          glyph: Glyph.check,
          height: 52,
        ),
      FriendRelation.friend => IbashoButton(
          key: const ValueKey<String>('addFriend.open'),
          label: l.addFriendOpenProfile,
          glyph: Glyph.arrowRight,
          tone: ButtonTone.accent,
          height: 52,
          minWidth: 240,
          cue: null,
          onPressed: () => pushChannelPage<void>(
            context,
            (_) => FriendProfileScreen(accountId: found.accountId!),
          ),
        ),
    };

    final layout = Layout.of(context);
    final tall = layout.tall;
    final window = tall ? math.min(layout.width * .46, 170.0) : 250.0;

    return Padding(
      padding: tall
          ? const EdgeInsets.fromLTRB(20, 18, 20, 18)
          : const EdgeInsets.symmetric(horizontal: 60, vertical: 26),
      child: _Beside(
        tall: tall,
        children: [
          // La ficha reducida: una ventana tenida del color de la persona con
          // su Tama dentro.
          SizedBox(
            width: window,
            height: window,
            child: GlossSurface(
              key: const ValueKey<String>('addFriend.card'),
              radius: tall ? window * .22 : 56,
              recessed: true,
              tint: accent,
              borderColor: Color.lerp(accent, T.dusk, .3)!,
              borderWidth: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tall ? window * .22 : 56),
                child: Transform.translate(
                  offset: Offset(0, tall ? window * .05 : 12),
                  child: CardTama(
                    accountId: found.accountId!,
                    card: card,
                    size: tall ? window * .96 : 240,
                    interactive: true,
                    joy: .8,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: tall ? 0 : 44, height: tall ? 14 : 0),
          Expanded(
            child: Column(
              crossAxisAlignment: tall ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tall ? Ty.title : Ty.display,
                ),
                SizedBox(height: tall ? 8 : 12),
                SizedBox(
                  width: tall ? 120 : 180,
                  height: 10,
                  child: GlossSurface(radius: 5, tint: accent, elevation: .6),
                ),
                SizedBox(height: tall ? 12 : 18),
                Text(
                  found.relation == FriendRelation.friend
                      ? l.addFriendAlreadyFriends
                      : found.relation == FriendRelation.requestedYou
                          ? l.addFriendTheyAsked
                          : l.addFriendPrivacy,
                  textAlign: tall ? TextAlign.center : TextAlign.start,
                  style: Ty.body.copyWith(color: T.inkSoft),
                ),
                SizedBox(height: tall ? 16 : 26),
                Row(children: [if (tall) Expanded(child: action) else action]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La ficha y sus datos: uno al lado del otro con ancho de sobra, uno encima
/// del otro cuando no lo hay.
class _Beside extends StatelessWidget {
  const _Beside({required this.tall, required this.children});

  final bool tall;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => tall
      // En vertical la ficha se lee de arriba abajo y se desplaza si el
      // movil es pequeño: nada se recorta.
      ? SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              children.first,
              for (final child in children.skip(1))
                if (child is Expanded) child.child else child,
            ],
          ),
        )
      : Row(children: children);
}
