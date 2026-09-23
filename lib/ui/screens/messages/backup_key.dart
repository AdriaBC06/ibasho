// Ibasho — la clave de respaldo: enseñarla una vez y recuperarla con ella.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/audio_service.dart';
import '../../../crypto/mnemonic.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/skin.dart';
import '../../../theme/tokens.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/gloss.dart';
import '../../widgets/overlays.dart';
import '../../widgets/panel.dart';
import '../../widgets/text_field.dart';

/// Las doce palabras, en rejilla numerada.
///
/// Numeradas porque el orden es parte de la clave, y en rejilla porque una
/// frase corrida de doce palabras se copia mal a papel: la gente se salta una
/// y luego no sabe cual.
class BackupWords extends StatelessWidget {
  const BackupWords({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    final columns = Layout.of(context).tall ? 2 : 3;
    final rows = (words.length / columns).ceil();

    return GlossSurface(
      radius: 12,
      tint: skin.accent,
      elevation: .5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < rows; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              Row(
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) const SizedBox(width: 14),
                    Expanded(
                      child: _Word(
                        number: row * columns + col + 1,
                        word: _at(row * columns + col),
                        accent: skin.accentDeep,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _at(int index) => index < words.length ? words[index] : '';
}

class _Word extends StatelessWidget {
  const _Word({required this.number, required this.word, required this.accent});

  final int number;
  final String word;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$number',
              textAlign: TextAlign.right,
              style: Ty.numeral(13, color: Ty.inkSoft),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ty.body.copyWith(color: accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
}

/// Lo que se ve una sola vez, recien creada la cuenta.
class BackupKeyPanel extends ConsumerStatefulWidget {
  const BackupKeyPanel({super.key, required this.words, this.onDone});

  final List<String> words;

  /// `null` cuando solo se esta consultando desde Ajustes: entonces no hay
  /// nada que confirmar, solo que cerrar.
  final VoidCallback? onDone;

  @override
  ConsumerState<BackupKeyPanel> createState() => _BackupKeyPanelState();
}

class _BackupKeyPanelState extends ConsumerState<BackupKeyPanel> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.words.join(' ')));
    AudioService.instance.play(Sfx.tick);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);

    return SectionCard(
      title: l.keysTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(l.keysIntro, style: Ty.body.copyWith(color: Ty.inkSoft)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: GlyphIcon(Glyph.lock, size: 16, color: T.warn),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.keysWarning,
                  style: Ty.caption.copyWith(color: T.warn),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          BackupWords(words: widget.words),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: layout.tall ? WrapAlignment.center : WrapAlignment.start,
            children: [
              IbashoButton(
                label: _copied ? l.keysCopied : l.keysCopy,
                glyph: _copied ? Glyph.check : Glyph.copy,
                onPressed: _copy,
              ),
              if (widget.onDone != null)
                IbashoButton(
                  label: l.keysConfirm,
                  glyph: Glyph.check,
                  tone: ButtonTone.accent,
                  onPressed: () {
                    AudioService.instance.play(Sfx.open);
                    ref.read(identityProvider.notifier).confirmPhraseSeen();
                    widget.onDone!();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lo que se ve en un aparato nuevo: la cuenta ya tiene claves y aqui no.
class RestoreKeyPanel extends ConsumerStatefulWidget {
  const RestoreKeyPanel({super.key});

  @override
  ConsumerState<RestoreKeyPanel> createState() => _RestoreKeyPanelState();
}

class _RestoreKeyPanelState extends ConsumerState<RestoreKeyPanel> {
  final TextEditingController _typed = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _startOver() async {
    final l = L.of(context)!;
    final confirmed = await askConfirmation(
      context,
      title: l.keysForgotTitle,
      body: l.keysForgotBody,
      confirmLabel: l.keysForgotConfirm,
      cancelLabel: l.actionCancel,
      tone: ButtonTone.warn,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _working = true;
      _error = null;
    });
    final ok = await ref.read(identityProvider.notifier).startOver();
    if (!mounted) return;
    setState(() => _working = false);
    if (!ok) showIbashoToast(context, l.keysForgotFailed, isError: true);
  }

  Future<void> _restore() async {
    final l = L.of(context)!;
    setState(() {
      _working = true;
      _error = null;
    });
    final failure =
        await ref.read(identityProvider.notifier).restoreWithPhrase(_typed.text);
    if (!mounted) return;

    final restoreFailed = ref.read(identityProvider).restoreFailed;
    setState(() {
      _working = false;
      _error = switch (failure?.failure) {
        MnemonicFailure.wordCount => l.keysErrorCount,
        MnemonicFailure.unknownWord => l.keysErrorWord(failure!.word ?? ''),
        MnemonicFailure.checksum => l.keysErrorChecksum,
        null => restoreFailed ? l.keysErrorNoMatch : null,
      };
    });
    AudioService.instance.play(_error == null ? Sfx.open : Sfx.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    // Lo que ya esta bien escrito se marca mientras se teclea: con doce
    // palabras a mano, saber cuantas van cayendo evita repasar la lista entera
    // para encontrar la que falla.
    final words = normalizeMnemonic(_typed.text);
    final good = words.where((w) => indexOfWord(w) >= 0).length;

    return SectionCard(
      title: l.keysRestoreTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(l.keysRestoreIntro, style: Ty.body.copyWith(color: Ty.inkSoft)),
          const SizedBox(height: 16),
          IbashoTextField(
            controller: _typed,
            label: l.keysRestoreHint,
            multiline: true,
            enabled: !_working,
            autofocus: true,
            error: _error,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _restore(),
          ),
          const SizedBox(height: 10),
          Text(
            '$good / $mnemonicWords',
            style: Ty.numeral(
              14,
              color: good == mnemonicWords ? IbashoSkin.of(context).accentDeep : Ty.inkSoft,
            ),
          ),
          const SizedBox(height: 16),
          IbashoButton(
            label: _working ? l.keysRestoreWorking : l.keysRestoreSubmit,
            glyph: Glyph.lock,
            tone: ButtonTone.accent,
            onPressed: _working || words.length != mnemonicWords ? null : _restore,
          ),
          const SizedBox(height: 10),
          // Sin las palabras no hay vuelta atras: se empieza con claves nuevas
          // y los mensajes de antes se quedan cerrados.
          IbashoButton(
            key: const ValueKey<String>('keys.forgot'),
            label: l.keysForgot,
            tone: ButtonTone.quiet,
            onPressed: _working ? null : _startOver,
          ),
        ],
      ),
    );
  }
}
