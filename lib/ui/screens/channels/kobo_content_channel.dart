// Ibasho — escaparate y lanzador del Kōbō Content Registry.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../extensions/content_models.dart';
import '../../../extensions/content_registry.dart';
import '../../../extensions/game_host_registry.dart';
import '../../../state/providers.dart';
import '../../../theme/type.dart';
import '../../layout.dart';
import '../../tama/tama_view.dart';
import '../../widgets/controls.dart';
import '../../widgets/glyphs.dart';
import '../../widgets/panel.dart';
import '../channel_route.dart';

class KoboContentChannel extends ConsumerStatefulWidget {
  const KoboContentChannel({super.key});

  @override
  ConsumerState<KoboContentChannel> createState() => _KoboContentChannelState();
}

class _KoboContentChannelState extends ConsumerState<KoboContentChannel> {
  final Map<ExtensionCosmeticSlot, String> _previewCosmetics =
      <ExtensionCosmeticSlot, String>{};

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final t = _KoboUi(locale);
    final layout = Layout.of(context);
    final asyncRegistry = ref.watch(extensionContentProvider);

    return ChannelScaffold(
      title: 'Kōbō',
      glyph: Glyph.star,
      child: IbashoScroll(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          layout.pick(26, 18),
          layout.gutter,
          42,
        ),
        child: Center(
          child: SizedBox(
            width: layout.pick(900, layout.column),
            child: asyncRegistry.when(
              loading: () => SectionCard(
                child: Center(child: Text(t.loading, style: Ty.lead)),
              ),
              error: (error, _) => SectionCard(
                child: Text('${t.loadError}: $error', style: Ty.caption),
              ),
              data: (registry) => _content(context, registry, locale, t),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ExtensionContentRegistry registry,
    String locale,
    _KoboUi t,
  ) {
    final tama = ref.watch(tamasProvider.select((state) => state.profileTama));
    final selectedCosmetics = <ExtensionCosmetic>[
      for (final cosmetic in registry.cosmetics)
        if (_previewCosmetics[cosmetic.slot] == cosmetic.contentId) cosmetic,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.registryTitle, style: Ty.lead),
              const SizedBox(height: 5),
              Text(t.registryBody, style: Ty.caption),
              const SizedBox(height: 12),
              Text(
                '${registry.backdrops.length} ${t.backdrops} · '
                '${registry.music.length} ${t.music} · '
                '${registry.cosmetics.length} ${t.cosmetics} · '
                '${registry.stickers.length} ${t.stickers} · '
                '${registry.levels.length} ${t.levels} · '
                '${registry.games.length} ${t.games}',
                style: Ty.micro,
              ),
            ],
          ),
        ),
        if (registry.games.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.gamesTitle,
            child: Column(
              children: [
                for (final game in registry.games)
                  SettingRow(
                    label: game.label(locale),
                    hint: game.describe(locale),
                    divider: game != registry.games.last,
                    control: IbashoButton(
                      label: t.open,
                      glyph: Glyph.play,
                      onPressed: KoboGameHostRegistry.supports(game.engine)
                          ? () => pushChannelPage<void>(
                              context,
                              (_) => KoboGameHostRegistry.build(
                                game: game,
                                levels: registry.levelsFor(game),
                                localeCode: locale,
                                text: (key, fallback) => registry.text(
                                  game.extensionId,
                                  key,
                                  locale,
                                  fallback: fallback,
                                ),
                              )!,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (registry.backdrops.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.backdropsTitle,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final backdrop in registry.backdrops)
                  IbashoButton(
                    label: backdrop.label(locale),
                    glyph: Glyph.moon,
                    onPressed: () => ref
                        .read(preferencesProvider.notifier)
                        .setBackdrop(backdrop.preferenceId),
                  ),
              ],
            ),
          ),
        ],
        if (registry.music.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.musicTitle,
            child: Column(
              children: [
                for (final track in registry.music)
                  SettingRow(
                    label: track.label(locale),
                    hint: '${track.author} · ${track.license}',
                    divider: track != registry.music.last,
                    control: IbashoButton(
                      label:
                          ref.watch(preferencesProvider).musicTrack ==
                              track.preferenceId
                          ? t.active
                          : t.use,
                      glyph: Glyph.note,
                      tone:
                          ref.watch(preferencesProvider).musicTrack ==
                              track.preferenceId
                          ? ButtonTone.accent
                          : ButtonTone.plain,
                      onPressed: () => ref
                          .read(preferencesProvider.notifier)
                          .setExtensionMusicTrack(
                            track.preferenceId,
                            track.filePath,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (registry.cosmetics.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.cosmeticsTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.cosmeticsLocal, style: Ty.caption),
                const SizedBox(height: 14),
                if (tama != null)
                  Center(
                    child: SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Center(
                            child: TamaView(
                              look: tama.look,
                              personality: tama.personality,
                              name: tama.name,
                              voice: tama.voice,
                              seed: tama.id.hashCode,
                              size: 220,
                              interactive: false,
                            ),
                          ),
                          for (final cosmetic in selectedCosmetics)
                            _CosmeticOverlay(
                              cosmetic: cosmetic,
                              canvasSize: 240,
                            ),
                        ],
                      ),
                    ),
                  )
                else
                  Text(t.noTama, style: Ty.caption),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final cosmetic in registry.cosmetics)
                      _AssetChoice(
                        label: cosmetic.label(locale),
                        path: cosmetic.filePath,
                        selected:
                            _previewCosmetics[cosmetic.slot] ==
                            cosmetic.contentId,
                        onPressed: () {
                          setState(() {
                            if (_previewCosmetics[cosmetic.slot] ==
                                cosmetic.contentId) {
                              _previewCosmetics.remove(cosmetic.slot);
                            } else {
                              _previewCosmetics[cosmetic.slot] =
                                  cosmetic.contentId;
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (registry.stickers.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.stickersTitle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.stickersLocal, style: Ty.caption),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final sticker in registry.stickers)
                      _StickerCard(sticker: sticker, locale: locale),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (registry.localizations.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: t.localizationTitle,
            child: Text(
              t.localizationBody(registry.localizations.length),
              style: Ty.caption,
            ),
          ),
        ],
      ],
    );
  }
}

class _CosmeticOverlay extends StatelessWidget {
  const _CosmeticOverlay({required this.cosmetic, required this.canvasSize});

  final ExtensionCosmetic cosmetic;
  final double canvasSize;

  @override
  Widget build(BuildContext context) {
    final width = canvasSize * cosmetic.widthFraction;
    return Positioned(
      left: canvasSize * cosmetic.anchorX - width / 2,
      top: canvasSize * cosmetic.anchorY - width / 2,
      width: width,
      height: width,
      child: IgnorePointer(
        child: Image.file(File(cosmetic.filePath), fit: BoxFit.contain),
      ),
    );
  }
}

class _AssetChoice extends StatelessWidget {
  const _AssetChoice({
    required this.label,
    required this.path,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final String path;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    child: Column(
      children: [
        SizedBox(
          width: 82,
          height: 82,
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Ty.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        IbashoButton(
          label: selected ? '✓' : '+',
          glyph: selected ? Glyph.check : Glyph.plus,
          tone: selected ? ButtonTone.accent : ButtonTone.quiet,
          onPressed: onPressed,
        ),
      ],
    ),
  );
}

class _StickerCard extends StatelessWidget {
  const _StickerCard({required this.sticker, required this.locale});

  final ExtensionSticker sticker;
  final String locale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112,
    child: Column(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: Image.file(File(sticker.filePath), fit: BoxFit.contain),
        ),
        const SizedBox(height: 5),
        Text(
          sticker.label(locale),
          style: Ty.caption,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _KoboUi {
  const _KoboUi(this.locale);

  final String locale;
  bool get en => locale.startsWith('en');
  String pick(String es, String enValue) => en ? enValue : es;

  String get loading => pick('cargando…', 'loading…');
  String get loadError => pick(
    'no se pudo leer el contenido Kōbō',
    'Kōbō content could not be loaded',
  );
  String get registryTitle => pick('registro de contenido', 'content registry');
  String get registryBody => pick(
    'Solo aparecen datos de paquetes activos y verificados; ningún paquete ejecuta código.',
    'Only data from active verified packages appears here; packages execute no code.',
  );
  String get backdrops => pick('fondos', 'backdrops');
  String get music => pick('pistas', 'tracks');
  String get cosmetics => pick('accesorios', 'cosmetics');
  String get stickers => pick('stickers', 'stickers');
  String get levels => pick('niveles', 'levels');
  String get games => pick('juegos', 'games');
  String get gamesTitle => pick('juegos y niveles', 'games and levels');
  String get backdropsTitle => pick('fondos', 'backdrops');
  String get musicTitle => pick('música local', 'local music');
  String get cosmeticsTitle => pick('accesorios locales', 'local cosmetics');
  String get stickersTitle => pick('stickers locales', 'local stickers');
  String get localizationTitle => pick('localización', 'localization');
  String get open => pick('abrir', 'open');
  String get use => pick('usar', 'use');
  String get active => pick('activa', 'active');
  String get noTama => pick(
    'elige un Tama de perfil para previsualizar accesorios',
    'choose a profile Tama to preview cosmetics',
  );
  String get cosmeticsLocal => pick(
    'Los accesorios Kōbō son una capa local: no conceden premios del gacha ni escriben inventario en Firebase.',
    'Kōbō cosmetics are a local layer: they do not grant gacha prizes or write inventory to Firebase.',
  );
  String get stickersLocal => pick(
    'Se previsualizan localmente. El protocolo de mensajes no envía stickers de extensiones todavía.',
    'They are previewed locally. The messaging protocol does not send extension stickers yet.',
  );
  String localizationBody(int count) => pick(
    '$count paquete(s) aporta(n) cadenas localizadas al registro.',
    '$count package(s) provide localized strings to the registry.',
  );
}
