// Ibasho — panel superior: contexto, reloj y estado.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../state/providers.dart';
import '../../theme/skin.dart';
import '../../theme/tokens.dart';
import '../../theme/type.dart';
import '../widgets/glyphs.dart';
import '../widgets/gloss.dart';
import 'channel_route.dart';
import 'channels/tamas_channel.dart';
import 'status_bar.dart';
import 'tama/tama_room_screen.dart';

/// Panel superior. Se adapta a las tres alturas del boton de ampliar.
class TopPanel extends ConsumerWidget {
  const TopPanel({super.key, required this.height});

  final double height;

  bool get _compact => height < 200;

  bool get _expanded => height > 430;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = L.of(context)!;
    final now = ref.watch(clockProvider);
    final profile = ref.watch(profileProvider.select((p) => p.profile));
    final username = ref.watch(sessionProvider.select((s) => s.username));
    final localeCode = ref.watch(preferencesProvider.select((p) => p.localeCode));

    final name = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : username;
    // Formato fijo de 24 h con dos digitos: el patron localizado de intl pone
    // "4:25" en espanol y "04:25" en ingles, y el reloj no debe saltar al
    // cambiar de idioma.
    final clock = DateFormat('HH:mm').format(now);
    final date = DateFormat.MMMMEEEEd(localeCode).format(now);

    if (_compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Row(
          children: [
            _TamaSlot(size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name, style: Ty.lead, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(_greeting(l, now), style: Ty.caption),
                ],
              ),
            ),
            Text(clock, style: Ty.clockSmall(T.ink)),
            const SizedBox(width: 26),
            const StatusBar(compact: true),
          ],
        ),
      );
    }

    final clockScale = _expanded ? 1.75 : 1.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(36, _expanded ? 34 : 26, 36, _expanded ? 30 : 22),
      child: Stack(
        children: [
          // Identidad, arriba a la izquierda.
          Align(
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TamaSlot(size: _expanded ? 124 : 88),
                SizedBox(width: _expanded ? 22 : 18),
                Padding(
                  padding: EdgeInsets.only(top: _expanded ? 10 : 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 420,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _expanded ? Ty.display : Ty.title,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(_greeting(l, now), style: Ty.caption.copyWith(fontSize: 15)),
                      if (profile != null && profile.statusMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: 420,
                            child: Text(
                              profile.statusMessage,
                              maxLines: _expanded ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: Ty.caption.copyWith(color: T.ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Estado, arriba a la derecha.
          const Align(alignment: Alignment.topRight, child: StatusBar()),

          // Reloj y fecha, abajo y al centro.
          Align(
            alignment: _expanded ? Alignment.center : Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: clockScale,
                  child: Text(clock, style: Ty.clock(T.ink)),
                ),
                SizedBox(height: _expanded ? 22 : 4),
                Text(
                  date,
                  style: (_expanded ? Ty.title : Ty.lead)
                      .copyWith(color: T.inkSoft, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),

          // Anuncio del sistema, si lo hay y si cabe.
          if (_expanded)
            Align(
              alignment: Alignment.bottomCenter,
              child: _Announcement(),
            ),
        ],
      ),
    );
  }

  static String _greeting(L l, DateTime now) {
    final hour = now.hour;
    if (hour < 5) return l.greetingNight;
    if (hour < 13) return l.greetingMorning;
    if (hour < 21) return l.greetingAfternoon;
    return l.greetingEvening;
  }
}

/// El hueco del Tama: el Tama de perfil, vivo, en su ventanita hundida.
///
/// Tocarlo abre su habitacion con el mismo gesto que un canal, creciendo desde
/// la ventanita. Si aun no hay Tama, se ve su silueta y abre el canal de Tamas.
class _TamaSlot extends ConsumerStatefulWidget {
  const _TamaSlot({required this.size});

  final double size;

  @override
  ConsumerState<_TamaSlot> createState() => _TamaSlotState();
}

class _TamaSlotState extends ConsumerState<_TamaSlot> {
  final GlobalKey _anchor = GlobalKey(debugLabel: 'top.tama');

  void _open() {
    final l = L.of(context)!;
    final skin = IbashoSkin.of(context);
    final tama = ref.read(tamasProvider).profileTama;
    openChannel(
      context,
      anchor: _anchor,
      tint: skin.accent,
      glyph: Glyph.tama,
      label: tama?.name ?? l.channelTamas,
      builder: (_) => tama == null
          ? const TamasChannel()
          : TamaRoomScreen(tamaId: tama.id),
    );
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: _anchor,
        child: TamaWindow(
          key: const ValueKey<String>('top.tama'),
          size: widget.size,
          onTap: _open,
        ),
      );
}

class _Announcement extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(announcementProvider).valueOrNull;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final skin = IbashoSkin.of(context);
    return GlossSurface(
      radius: 18,
      recessed: true,
      tint: skin.accent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Ty.caption.copyWith(color: T.ink, fontSize: 14),
      ),
    );
  }
}
