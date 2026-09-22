// Ibasho — la cancion de cada juego, que se desbloquea al oirla.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_service.dart';
import '../state/providers.dart';

/// Pone [track] en lugar de la musica de ambiente mientras el juego esta
/// abierto, con el mismo fundido que la musica de un perfil, y la anade a la
/// biblioteca de la cuenta la primera vez: a partir de ahi se puede elegir
/// para el menu o para el perfil.
///
/// Si [track] cambia sin desmontarse (Nihongo tiene una para el menu y otra
/// para jugar), pasa a la nueva con el mismo fundido y la desbloquea tambien.
class GameMusic extends ConsumerStatefulWidget {
  const GameMusic({super.key, required this.track, required this.child});

  final MusicTrack track;
  final Widget child;

  @override
  ConsumerState<GameMusic> createState() => _GameMusicState();
}

class _GameMusicState extends ConsumerState<GameMusic> {
  @override
  void initState() {
    super.initState();
    _play(widget.track);
  }

  @override
  void didUpdateWidget(GameMusic old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) _play(widget.track);
  }

  void _play(MusicTrack track) {
    unawaited(AudioService.instance.playProfileTrack(track));
    // Se lee despues del cuadro: tocar un provider durante el montaje o la
    // reconstruccion lo marca como sucio a mitad de construccion.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final library = ref.read(musicLibraryProvider.notifier);
      if (ref.read(musicLibraryProvider).loaded) {
        unawaited(library.markHeard(track));
      } else {
        // Sin la biblioteca cargada no se sabe si ya estaba: se espera a ella.
        ref.listenManual(musicLibraryProvider.select((m) => m.loaded), (_, loaded) {
          if (loaded && mounted) unawaited(library.markHeard(track));
        });
      }
    });
  }

  @override
  void dispose() {
    unawaited(AudioService.instance.endProfileTrack());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
