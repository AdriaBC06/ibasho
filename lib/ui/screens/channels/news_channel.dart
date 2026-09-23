// Ibasho — canal de noticias: el tablon de la casa.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../state/providers.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';
import '../news/news_composer.dart';
import '../news/news_entry.dart';

/// El tablon: novedades de version, avisos y encuestas, de lo mas nuevo a lo
/// mas viejo.
///
/// Es una sola columna que se desplaza, no una rejilla paginada: aqui se lee
/// seguido y las entradas no miden lo mismo unas que otras. El admin publica
/// desde arriba, en la misma pantalla que lee todo el mundo.
class NewsChannel extends ConsumerStatefulWidget {
  const NewsChannel({super.key});

  @override
  ConsumerState<NewsChannel> createState() => _NewsChannelState();
}

class _NewsChannelState extends ConsumerState<NewsChannel> {
  @override
  void initState() {
    super.initState();
    // Abrir el canal ya cuenta como haberlo leido. Se apunta despues del
    // primer fotograma para no tocar el estado mientras se monta el arbol.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  void _markRead() {
    if (!mounted) return;
    unawaited(ref.read(newsProvider.notifier).markRead());
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context)!;
    final layout = Layout.of(context);
    final state = ref.watch(newsProvider);
    final isAdmin = ref.watch(sessionProvider.select((s) => s.isAdmin));

    // Las entradas llegan por el stream, casi siempre despues de que la
    // pantalla este montada: cada vez que cambia el tablon se vuelve a marcar
    // como visto, que es lo unico que apaga la chapa del canal.
    ref.listen<int>(
      newsProvider.select((n) => n.items.length),
      (_, _) => _markRead(),
    );

    return ChannelScaffold(
      title: l.newsTitle,
      glyph: Glyph.news,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          layout.pick(28, 18),
          layout.gutter,
          44,
        ),
        child: Center(
          child: SizedBox(
            width: layout.pick(820, layout.column),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isAdmin) ...[
                  const NewsComposer(),
                  SizedBox(height: layout.pick(26, 20)),
                ],
                if (!state.loaded)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: Text(l.loading, style: Ty.caption)),
                  )
                else if (state.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        l.newsEmpty,
                        textAlign: TextAlign.center,
                        style: Ty.body.copyWith(color: Ty.inkSoft),
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < state.items.length; i++) ...[
                    if (i > 0) SizedBox(height: layout.pick(22, 16)),
                    NewsEntry(
                      key: ValueKey<String>(state.items[i].id),
                      item: state.items[i],
                      isAdmin: isAdmin,
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
