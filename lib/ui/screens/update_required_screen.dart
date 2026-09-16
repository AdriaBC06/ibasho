// Ibasho — pantalla de version antigua.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({super.key});

  Future<void> _open(String url) async {
    AudioService.instance.play(Sfx.open);
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint('Ibasho: no se ha podido abrir la descarga ($e)');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                      Text(l.appName, style: Ty.logo(34, T.ink)),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(l.updateTitle, style: Ty.title, textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  Text(
                    l.updateBody(minimum),
                    textAlign: TextAlign.center,
                    style: Ty.body.copyWith(color: T.inkSoft),
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
                            onPressed: () => _open(url),
                          ),
                        ),
                      ],
                    ),
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
            style: Ty.numeral(24, color: current ? T.onAccent : T.inkSoft, weight: FontWeight.w700),
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
