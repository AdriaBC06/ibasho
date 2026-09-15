// Ibasho — dialogos y avisos flotantes.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import 'controls.dart';
import 'gloss.dart';

/// Ruta de un dialogo. Vive dentro del lienzo, asi que se escala con el.
class _IbashoModalRoute<R> extends PopupRoute<R> {
  _IbashoModalRoute({required this.builder, required this.reducedMotion});

  final WidgetBuilder builder;
  final bool reducedMotion;

  @override
  Color? get barrierColor => T.scrim;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'modal';

  @override
  Duration get transitionDuration =>
      reducedMotion ? T.reduced : const Duration(milliseconds: 240);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondary) =>
      Center(child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondary, Widget child) {
    final fade = FadeTransition(opacity: animation, child: child);
    if (reducedMotion) return fade;
    return ScaleTransition(
      scale: Tween<double>(begin: .93, end: 1).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
      ),
      child: fade,
    );
  }
}

Future<R?> showIbashoModal<R>(BuildContext context, WidgetBuilder builder) =>
    Navigator.of(context).push(
      _IbashoModalRoute<R>(
        builder: builder,
        reducedMotion: IbashoSkin.of(context).reducedMotion,
      ),
    );

/// Panel de un dialogo: el mismo plastico que el resto del entorno.
class IbashoDialog extends StatelessWidget {
  const IbashoDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.width = 520,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: GlossSurface(
          radius: 28,
          elevation: 2.4,
          padding: const EdgeInsets.fromLTRB(34, 30, 34, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Ty.title),
              const SizedBox(height: 14),
              body,
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    actions[i],
                  ],
                ],
              ),
            ],
          ),
        ),
      );
}

/// Pregunta de si o no.
Future<bool> askConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  ButtonTone tone = ButtonTone.accent,
}) async {
  final answer = await showIbashoModal<bool>(
    context,
    (context) => IbashoDialog(
      title: title,
      body: Text(body, style: Ty.body.copyWith(color: T.inkSoft)),
      actions: [
        IbashoButton(
          label: cancelLabel,
          tone: ButtonTone.quiet,
          cue: Sfx.back,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        IbashoButton(
          label: confirmLabel,
          tone: tone,
          minWidth: 140,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return answer ?? false;
}

/// Aviso corto en la parte baja del lienzo.
///
/// Es el sustituto del `SnackBar`: no bloquea, no aparta nada de sitio y se va
/// solo.
void showIbashoToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;
  final skin = IbashoSkin.of(context);
  final notifier = ValueNotifier<bool>(false);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 0,
      right: 0,
      bottom: 44,
      child: IgnorePointer(
        child: Center(
          child: ValueListenableBuilder<bool>(
            valueListenable: notifier,
            builder: (context, visible, child) => AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: skin.motion(const Duration(milliseconds: 220)),
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, .35),
                duration: skin.motion(const Duration(milliseconds: 260)),
                curve: skin.curve(Curves.easeOutCubic),
                child: child,
              ),
            ),
            child: GlossSurface(
              radius: 24,
              elevation: 2,
              tint: isError ? T.warn : skin.accent,
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              child: Text(
                message,
                style: Ty.body.copyWith(
                  color: T.onAccent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  notifier.value = true;
  Future<void>.delayed(const Duration(milliseconds: 2200), () async {
    notifier.value = false;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    entry.remove();
    notifier.dispose();
  });
}
