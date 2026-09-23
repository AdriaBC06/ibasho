// Ibasho — pantalla de version antigua.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../audio/audio_service.dart';
import '../../core/version.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../state/update_gate.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../widgets/controls.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import '../widgets/logo.dart';
import '../widgets/panel.dart';
import '../layout.dart';

/// Esta build es mas antigua que la minima exigida: no se deja pasar.
///
/// Sustituye a todo lo demas (login y entorno). Si el admin baja la version
/// minima o se instala la nueva, desaparece sola.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  ConsumerState<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen> {
  bool _failed = false;
  bool _copied = false;

  /// Abre la pagina de descargas en el navegador del sistema.
  ///
  /// Con `url_launcher` y no con `Process.start`: aquello solo sabia de
  /// escritorio —tenia rama para Linux, macOS y Windows y **ninguna para
  /// Android**—, asi que en el movil el boton sonaba y no hacia nada, que es
  /// justo donde mas falta hace. De regalo, esto tambien es lo que abre bien
  /// un navegador en un Linux sin `xdg-open`.
  ///
  /// `false` si no se ha podido: entonces la pantalla se queda con la
  /// direccion escrita, que es lo unico que no puede fallar.
  Future<bool> _open(String url) async {
    AudioService.instance.play(Sfx.open);
    try {
      final target = Uri.tryParse(url);
      if (target == null) return false;
      return await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Ibasho: no se ha podido abrir la descarga ($e)');
      return false;
    }
  }

  Future<void> _download(String url) async {
    final ok = await _open(url);
    if (mounted) setState(() => _failed = !ok);
  }

  Future<void> _copy(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    AudioService.instance.play(Sfx.tick);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final layout = Layout.of(context);
    final tall = layout.tall;
    final requirement = ref.watch(updateRequirementProvider).valueOrNull;
    final minimum = requirement?.minVersion.toString() ?? '';
    final url = requirement?.url;

    return Bezel(
      child: Center(
        child: SizedBox(
          width: math.min(640, layout.width - layout.gutter * 2),
          child: ScreenPanel(
            child: Padding(
              padding: layout.pick(
                const EdgeInsets.fromLTRB(48, 40, 48, 38),
                const EdgeInsets.fromLTRB(22, 26, 22, 24),
              ),
              child: Column(
                key: const ValueKey<String>('update.required'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IbashoMark(size: 58, accent: skin.accent),
                      const SizedBox(width: 16),
                      Text(l.appName, style: Ty.logo(34, Ty.ink)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(l.updateTitle, style: Ty.title, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    l.updateBody(minimum),
                    textAlign: TextAlign.center,
                    style: Ty.body.copyWith(color: Ty.inkSoft),
                  ),
                  const SizedBox(height: 24),
                  // Las dos versiones y la flecha: si no caben de lado, la
                  // flecha se queda igual y las pastillas se reparten.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Fit(
                        tall: tall,
                        child: _VersionChip(
                          label: l.updateYours,
                          version: appVersion,
                          current: false,
                        ),
                      ),
                      SizedBox(width: layout.pick(14, 10)),
                      GlyphIcon(Glyph.arrowRight, size: 22, color: skin.accentDeep),
                      SizedBox(width: layout.pick(14, 10)),
                      _Fit(
                        tall: tall,
                        child: _VersionChip(
                          label: l.updateNeeded,
                          version: minimum,
                          current: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  if (url != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Fit(
                          tall: tall,
                          child: IbashoButton(
                            key: const ValueKey<String>('update.download'),
                            label: l.updateDownload,
                            glyph: Glyph.download,
                            tone: ButtonTone.accent,
                            height: 52,
                            minWidth: layout.pick(240, 0),
                            cue: null,
                            onPressed: () => _download(url),
                          ),
                        ),
                      ],
                    ),
                  // La direccion, escrita y copiable, pase lo que pase con el
                  // boton. Es el unico camino que no depende de que haya un
                  // navegador que abrir, ni de que esta build sepa abrirlo:
                  // quien se quede tirado siempre puede teclearla en otro
                  // aparato.
                  if (url != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _failed ? l.updateOpenFailed : l.updateOrVisit,
                      textAlign: TextAlign.center,
                      style: Ty.caption.copyWith(color: _failed ? T.warn : Ty.inkSoft),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          // Texto pelado, no `SelectableText`: eso es de
                          // Material y aqui no entra ni uno. Para llevarsela
                          // esta el boton de al lado.
                          child: Text(
                            url,
                            textAlign: TextAlign.center,
                            style: Ty.body.copyWith(color: skin.accentDeep),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconPill(
                          glyph: _copied ? Glyph.check : Glyph.copy,
                          semanticLabel: _copied ? l.actionCopied : l.actionCopy,
                          onPressed: () => _copy(url),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(l.updateHint, textAlign: TextAlign.center, style: Ty.caption),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.label, required this.version, required this.current});

  final String label;
  final String version;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final skin = IbashoSkin.of(context);
    return Column(
      children: [
        Text(label, style: Ty.label),
        const SizedBox(height: 6),
        GlossSurface(
          radius: 18,
          recessed: !current,
          tint: current ? skin.accent : null,
          elevation: current ? 1.2 : 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            version,
            style: Ty.numeral(24, color: current ? T.onAccent : Ty.inkSoft, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// En vertical cede el ancho que haga falta; en horizontal ocupa lo suyo.
class _Fit extends StatelessWidget {
  const _Fit({required this.tall, required this.child});

  final bool tall;
  final Widget child;

  @override
  Widget build(BuildContext context) => tall ? Flexible(child: child) : child;
}
