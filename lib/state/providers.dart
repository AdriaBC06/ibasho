// Ibasho — cableado de dependencias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/gacha.dart' show TicketKind;
import '../backend/ibasho_backend.dart';
import '../backend/koen_bonds.dart' show KoenFriendLevel;
import '../backend/koen_care.dart';
import '../backend/koen_duo.dart';
import '../backend/live_tree.dart' show applyDatabaseEvent;
import '../backend/koen_rewards.dart' show koenGame;
import '../backend/leaderboards.dart';
import '../backend/rest_ibasho_backend.dart';
import '../backend/shop.dart';
import '../backend/tama.dart';
import '../extensions/backdrop_pack.dart';
import '../storage/secure_store.dart';
import '../storage/settings_store.dart';
import '../theme/tokens.dart';
import 'accent_sync.dart';
import 'admin.dart';
import 'card.dart';
import 'channel_order.dart';
import 'coins.dart';
import 'daily_gift.dart';
import 'rewards.dart';
import 'conversation.dart';
import 'friends.dart';
import 'gacha.dart';
import '../games/hatarakitama/hataraki_engine.dart' show HState;
import 'hataraki.dart';
import 'identity.dart';
import 'koen.dart';
import 'koen_duo.dart';
import 'koro.dart';
import 'leaderboards.dart';
import 'login_bonus.dart';
import 'messages.dart';
import 'missions.dart';
import 'news.dart';
import 'pantry.dart';
import 'suggestions.dart';
import 'music_library.dart';
import 'preferences.dart';
import 'presence.dart';
import 'profile.dart';
import 'session.dart';
import 'shop.dart';
import 'system_status.dart';
import 'tamas.dart';

/// Se sobrescriben en `main()`, cuando ya se han abierto los archivos.
final secureStoreProvider = Provider<SecureStore>(
  (_) => throw UnimplementedError('secureStoreProvider sin sobrescribir'),
);
final settingsStoreProvider = Provider<SettingsStore>(
  (_) => throw UnimplementedError('settingsStoreProvider sin sobrescribir'),
);
final initialPreferencesProvider = Provider<Preferences>(
  (_) =>
      throw UnimplementedError('initialPreferencesProvider sin sobrescribir'),
);

/// El unico punto del arbol que sabe que existe REST.
final backendProvider = Provider<IbashoBackend>((ref) {
  final backend = RestIbashoBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

final preferencesProvider =
    StateNotifierProvider<PreferencesController, Preferences>(
      (ref) => PreferencesController(
        ref.watch(settingsStoreProvider),
        ref.watch(initialPreferencesProvider),
      ),
    );

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(
    backend: ref.watch(backendProvider),
    store: ref.watch(secureStoreProvider),
    preferences: ref.watch(preferencesProvider.notifier),
  ),
);

final clockProvider = StateNotifierProvider<Clock, DateTime>((_) => Clock());

/// De donde sale la bateria. Los tests la sustituyen: alli no hay plugins.
final batteryWatchProvider = Provider<BatteryWatch>(
  (_) => PluginBatteryWatch(),
);

final systemStatusProvider =
    StateNotifierProvider<SystemStatusController, SystemStatus>(
      (ref) => SystemStatusController(
        ref.watch(backendProvider),
        battery: ref.watch(batteryWatchProvider),
      ),
    );

/// Vive mientras dure la sesion de un uid concreto.
final profileProvider = StateNotifierProvider<ProfileController, ProfileState>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  return ProfileController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    defaultLocale: ref.read(preferencesProvider).localeCode,
    cardOf: (profile) => cardForProfile(ref, profile),
  );
});

final adminProvider = StateNotifierProvider<AdminController, AdminState>((ref) {
  ref.watch(sessionProvider.select((s) => s.uid));
  return AdminController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// Idioma activo. Manda la preferencia local, que es la que se cambia en
/// caliente; el perfil la sincroniza cuando se guarda.
final localeProvider = Provider<Locale>(
  (ref) => Locale(ref.watch(preferencesProvider.select((p) => p.localeCode))),
);

/// Los Tamas de la cuenta en curso.
final tamasProvider = StateNotifierProvider<TamasController, TamasState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  return TamasController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    cardOf: (id, color) => cardForTama(ref, id, color),
    consumeFood: (food) => ref.read(pantryProvider.notifier).consume(food),
  );
});

/// La despensa de la cuenta: unidades de cada comida.
final pantryProvider =
    StateNotifierProvider<PantryController, Map<TamaFood, int>>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return PantryController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
      );
    });

/// Hora con resolucion de minuto, para el humor de los Tamas. El humor se
/// calcula con esto en cada vista; no se escribe nunca.
final moodClockProvider = Provider<DateTime>((ref) {
  final minute = ref.watch(
    clockProvider.select(
      (t) => t.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute,
    ),
  );
  return DateTime.fromMillisecondsSinceEpoch(
    minute * Duration.millisecondsPerMinute,
  );
});

/// Color de acento.
///
/// Si el perfil sigue al Tama, sale del color del Tama de perfil, ajustado para
/// que se lea sobre los paneles: asi una edicion del Tama tiñe el entorno en
/// cuanto llega, sin esperar a ninguna escritura. Si no, manda el del perfil.
/// Mientras nada de eso ha llegado por red se usa el ultimo conocido en esta
/// maquina, para que el arranque no pinte cian y luego salte al color de verdad.
final accentProvider = Provider<Color>((ref) {
  final profile = ref.watch(profileProvider.select((p) => p.profile));
  if (profile != null) {
    if (profile.accentFollowsTama == true) {
      final tamaColor = ref.watch(
        tamasProvider.select((t) => t.profileTama?.look.color),
      );
      if (tamaColor != null) return accentForTama(tamaColor);
    }
    return profile.accent;
  }
  final cached = ref.watch(preferencesProvider.select((p) => p.accentHex));
  return parseAccent(cached) ?? T.cyan;
});

/// `#RRGGBB` a color, o `null` si no es valido.
Color? parseAccent(String hex) {
  final clean = hex.replaceFirst('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Anuncio del sistema, si lo hay. Se sigue en tiempo real.
///
/// Es opcional en el modelo de datos: cuando no existe el nodo, el panel
/// superior simplemente no ensena nada.
final announcementProvider = StreamProvider<String?>((ref) async* {
  final phase = ref.watch(sessionProvider.select((s) => s.phase));
  if (phase != SessionPhase.active) {
    yield null;
    return;
  }
  final backend = ref.watch(backendProvider);
  final session = ref.watch(sessionProvider.notifier);

  String? textOf(Object? raw) =>
      raw is Map ? raw['text'] as String? : (raw is String ? raw : null);

  try {
    yield textOf(
      await backend.read(
        '/system/announcement',
        idToken: await session.freshToken(),
      ),
    );
  } catch (_) {
    yield null;
  }

  await for (final event in backend.watch(
    '/system/announcement',
    token: session.freshToken,
  )) {
    if (event.path == '/') {
      yield textOf(event.data);
    } else if (event.path == '/text') {
      yield event.data as String?;
    }
  }
});

/// Cambia el idioma en caliente y lo guarda en los dos sitios donde vive: la
/// preferencia local, que es la que manda al pintar, y el perfil, para que viaje
/// con la cuenta y no se revierta en el proximo arranque.
Future<void> changeLanguage(WidgetRef ref, String code) async {
  await ref.read(preferencesProvider.notifier).setLocale(code);
  final profile = ref.read(profileProvider).profile;
  if (profile != null && profile.locale != code) {
    await ref
        .read(profileProvider.notifier)
        .save(profile.copyWith(locale: code));
  }
}

/// Musica del menu y canciones desbloqueadas de la cuenta en curso.
final musicLibraryProvider =
    StateNotifierProvider<MusicLibraryController, MusicLibraryState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      final controller = MusicLibraryController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        preferences: ref.watch(preferencesProvider.notifier),
      );
      // Las musicas ganadas en el gacha (`mu_<id>` en la coleccion) pasan a la
      // biblioteca. En la 0.6.0 solo las veia la lista de Ajustes.
      ref.listen<Map<String, int>>(
        gachaProvider.select((g) => g.prizes),
        (_, prizes) => unawaited(controller.adoptPrizes(prizes.keys)),
        fireImmediately: true,
      );
      return controller;
    });

/// Orden de los canales del HOME, elegido por la cuenta.
final channelOrderProvider =
    StateNotifierProvider<ChannelOrderController, ChannelOrderState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      return ChannelOrderController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
      );
    });

/// Presencia propia. Vive mientras dure la sesion activa de una cuenta; al
/// salir se cierra su conexion y el servidor marca la desconexion.
final presenceProvider =
    StateNotifierProvider<PresenceController, PresenceStatus>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      final active = ref.watch(
        sessionProvider.select((s) => s.phase == SessionPhase.active),
      );
      return PresenceController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        active: active,
      );
    });

/// Amigos y solicitudes de la cuenta en curso.
final friendsProvider = StateNotifierProvider<FriendsController, FriendsState>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return FriendsController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    unshare: (friend) => ref.read(tamasProvider.notifier).unsharePaths(friend),
  );
});

/// Solicitudes pendientes de responder: la insignia del canal de amigos.
final pendingRequestsProvider = Provider<int>(
  (ref) => ref.watch(friendsProvider.select((f) => f.incoming.length)),
);

// --- 0.4.0: cifrado, mensajes, noticias, sugerencias y monedas -------------

/// Las claves de cifrado de la cuenta en este aparato.
///
/// Va antes que la mensajeria a proposito: sin claves no hay conversacion que
/// abrir, y quien las mira decide si hay que enseñar la frase de respaldo.
final identityProvider =
    StateNotifierProvider<IdentityController, IdentityState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return IdentityController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        store: ref.watch(secureStoreProvider),
      );
    });

/// El canal de mensajes: quien tiene algo sin leer y como esta el grupo.
final messagesProvider =
    StateNotifierProvider<MessagesController, MessagesState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return MessagesController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
      );
    });

/// Una conversacion abierta. Se crea al entrar y se tira al salir: lo
/// descifrado no sobrevive al cierre del canal.
final conversationProvider =
    StateNotifierProvider.family<
      ConversationController,
      ConversationState,
      ConversationTarget
    >((ref, target) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      return ConversationController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        // Solo las claves, nunca el estado entero de la identidad: con el, la
        // conversacion se rehacia —y se volvia a descifrar— a cada cambio.
        keys: ref.watch(identityProvider.select((i) => i.keys)),
        target: target,
      );
    });

/// El tablon de noticias y encuestas.
final newsProvider = StateNotifierProvider<NewsController, NewsState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return NewsController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// El buzon de sugerencias.
final suggestionsProvider =
    StateNotifierProvider<SuggestionsController, SuggestionsState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return SuggestionsController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        isAdmin: ref.watch(sessionProvider.select((s) => s.isAdmin)),
      );
    });

/// Las monedas de la cuenta en curso.
final coinsProvider = StateNotifierProvider<CoinsController, int>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return CoinsController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// El Yatai: precios y juegos comprados, y la compra en si.
final shopProvider = StateNotifierProvider<ShopController, ShopState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return ShopController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    coinsOf: () => ref.read(coinsProvider),
    pantryQtyOf: (food) => ref.read(pantryProvider)[food] ?? 0,
    unlockedFoodsOf: () => ref.read(unlockedFoodsProvider),
    ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
    koroSlotsOf: () => ref.read(koroProvider).slots,
    prizeCopiesOf: (key) => ref.read(gachaProvider).copiesOf(key),
  );
});

/// El gacha: tickets, tiradas, el deposito de bolas y el Catalogo.
final gachaProvider = StateNotifierProvider<GachaController, GachaState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return GachaController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// Tema propio de un juego mientras esta abierto (solo Odori lo tiene): el
/// `id` de un fondo, `''` para ninguno o `null` para seguir al del menu.
final gameThemeProvider = StateProvider<String?>((ref) => null);

/// El fondo puesto en Ajustes (el `id` de `Backdrop`), o vacio. Uno que la
/// coleccion ya no tiene (un admin que se lo ha quitado) cuenta como vacio.
/// Con un juego de tema propio abierto, manda el del juego.
final backdropIdProvider = Provider<String>((ref) {
  final String? game = ref.watch(gameThemeProvider);
  final String menu = ref.watch(
    preferencesProvider.select((p) => p.backdropId),
  );
  final chosen = game ?? menu;
  if (chosen.isEmpty) return '';

  // El contenido Kōbō vive en el registro local, no en la colección del
  // gacha. Un fondo ext: solo existe mientras su paquete y versión activa lo
  // declaren; los fondos nativos conservan exactamente la regla original.
  if (chosen.startsWith('ext:')) {
    final extensionBackdrops =
        ref.watch(extensionBackdropsProvider).asData?.value ??
        const <ExtensionBackdrop>[];
    return resolveBackdropAvailability(
      chosen: chosen,
      nativeOwned: false,
      extensionBackdrops: extensionBackdrops,
    );
  }

  final gone = ref.watch(
    gachaProvider.select((g) => g.loaded && !g.owns('bg_$chosen')),
  );
  return resolveBackdropAvailability(
    chosen: chosen,
    nativeOwned: !gone,
    extensionBackdrops: const <ExtensionBackdrop>[],
  );
});

/// Las misiones diarias y semanales: señales, cobros y lo que dan.
final missionsProvider =
    StateNotifierProvider<MissionsController, MissionsState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return MissionsController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
      );
    });

/// Las clasificaciones de los minijuegos: tablas diaria y semanal, con
/// premio en tickets para el top 3.
final leaderboardsProvider =
    StateNotifierProvider<LeaderboardsController, LeaderboardsState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return LeaderboardsController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
      );
    });

/// Los premios de los juegos: monedas por ganar, con tope diario.
final rewardsProvider = StateNotifierProvider<RewardsController, RewardsState>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return RewardsController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    coinsOf: () => ref.read(coinsProvider),
  );
});

/// El bono diario: unas monedas por entrar, una vez al dia.
final loginBonusProvider =
    StateNotifierProvider<LoginBonusController, LoginBonusState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return LoginBonusController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        coinsOf: () => ref.read(coinsProvider),
      );
    });

/// El regalo diario del Yatai: comida, un gachaken y un saquito de monedas.
final dailyGiftProvider =
    StateNotifierProvider<DailyGiftController, DailyGiftState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return DailyGiftController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        coinsOf: () => ref.read(coinsProvider),
        ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
        pantryOf: (food) => ref.read(pantryProvider)[food] ?? 0,
      );
    });

/// Los juegos comprados, por id: la rejilla los ensena como regalo o canal
/// segun su estado.
final installedGamesProvider = Provider<Map<String, GameInstall>>(
  (ref) => ref.watch(shopProvider.select((s) => s.games)),
);

/// Conversaciones con algo sin leer: la chapa del canal de mensajes.
final unreadMessagesProvider = Provider<int>(
  (ref) => ref.watch(messagesProvider.select((m) => m.unreadCount)),
);

/// Entradas del tablon sin ver: la chapa del canal de noticias.
final unreadNewsProvider = Provider<int>(
  (ref) => ref.watch(newsProvider.select((n) => n.unreadCount)),
);

/// Sugerencias esperando veredicto. Solo se llena si quien mira es admin, asi
/// que la chapa del canal de sugerencias solo se le enciende a el.
final pendingSuggestionsProvider = Provider<int>(
  (ref) => ref.watch(suggestionsProvider.select((s) => s.pending.length)),
);

/// Las canciones de Tamakoro y los huecos de la cuenta.
final koroProvider = StateNotifierProvider<KoroController, KoroState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  return KoroController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
  );
});

/// La partida de Hatarakitama: oficios, almacén, Tamas trabajando y
/// expediciones.
final hatarakiProvider =
    StateNotifierProvider<HatarakiController, HatarakiState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
      return HatarakiController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        tamasOf: () => ref.read(tamasProvider).tamas,
        tamasLoaded: () => ref.read(tamasProvider).loaded,
        gachakenOf: () =>
            ref.read(gachaProvider).ticketsOf(TicketKind.gachaken),
        onScores: (day, week, allTime) => unawaited(
          ref
              .read(leaderboardsProvider.notifier)
              .submitScore(
                LeaderboardGame.hataraki,
                day,
                weeklyScore: week,
                allTimeScore: allTime,
              ),
        ),
      );
    });

/// Tama Kōen: el parque propio y los de los amigos. Se lee al abrir el canal.
final koenProvider = StateNotifierProvider<KoenController, KoenState>((ref) {
  ref.watch(sessionProvider.select((s) => s.accountId));
  ref.watch(sessionProvider.select((s) => s.phase == SessionPhase.active));
  return KoenController(
    backend: ref.watch(backendProvider),
    session: ref.watch(sessionProvider.notifier),
    rewardsOf: () => ref.read(rewardsProvider),
    claimCoins: (amount) => ref
        .read(rewardsProvider.notifier)
        .claim(game: koenGame, amount: amount),
    pantryOf: (food) => ref.read(pantryProvider)[food] ?? 0,
    ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
    isMine: (id) => ref.read(tamasProvider).find(id) != null,
    pet: (id) => unawaited(ref.read(tamasProvider.notifier).pet(id)),
    coinsOf: () => ref.read(coinsProvider),
    owns: (key) => ref.read(gachaProvider).owns(key),
    duoOf: (id) => koenDuoOfTama(ref.read(koenDuosProvider), id)?.mateOf(id),
  );
});

/// El nivel de amistad del parque con cada amigo, para su insignia en la
/// lista de amigos y en su perfil. Con el parque ya leído, el suyo; si no,
/// una lectura puntual de `koen/friends`.
final koenFriendLevelsProvider = FutureProvider<Map<String, KoenFriendLevel>>((
  ref,
) async {
  final levels = ref.watch(
    koenProvider.select((k) => k.loaded && !k.demo ? k.levels : null),
  );
  if (levels != null) return levels;
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  if (me.isEmpty) return const <String, KoenFriendLevel>{};
  try {
    final raw = await ref
        .read(backendProvider)
        .read(
          '/users/$me/koen/friends',
          idToken: await ref.read(sessionProvider.notifier).freshToken(),
        );
    return KoenController.levelsFrom(raw);
  } catch (_) {
    return const <String, KoenFriendLevel>{};
  }
});

/// Los puntos de amistad del parque con [friend], sumando los de los dos.
/// Con el parque ya leído, los suyos; si no, dos lecturas puntuales.
final koenFriendPointsProvider = FutureProvider.family<int, String>((
  ref,
  friend,
) async {
  final park = ref.watch(
    koenProvider.select((k) => k.loaded && !k.demo ? k : null),
  );
  if (park != null)
    return (park.mates[friend]?.p ?? 0) + (park.theirs[friend] ?? 0);
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  if (me.isEmpty) return 0;
  final backend = ref.read(backendProvider);
  final token = await ref.read(sessionProvider.notifier).freshToken();
  Future<int> half(String path) => backend
      .read(path, idToken: token)
      .then((v) => v is num ? v.toInt() : 0, onError: (Object _) => 0);
  final both = await Future.wait([
    half('/users/$me/koen/friends/$friend/p'),
    half('/users/$friend/koen/friends/$me/p'),
  ]);
  return both[0] + both[1];
});

/// Las ofertas de cuidar a medias que han llegado al buzón
/// (`koenInbox`). Salen de la conexión de la cuenta: no abren otra.
final koenOffersProvider = StreamProvider<List<KoenOffer>>((ref) async* {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  final active = ref.watch(
    sessionProvider.select((s) => s.phase == SessionPhase.active),
  );
  if (me.isEmpty || !active) {
    yield const <KoenOffer>[];
    return;
  }
  Object? tree;
  await for (final event
      in ref
          .read(backendProvider)
          .watch(
            '/users/$me/koenInbox',
            token: ref.read(sessionProvider.notifier).freshToken,
          )) {
    tree = applyDatabaseEvent(tree, event);
    yield KoenOffer.listFrom(tree);
  }
});

/// Las ofertas inventadas del parque de prueba («demo», solo en depuración).
final koenDemoOffersProvider = StateProvider<List<KoenOffer>>(
  (ref) => const <KoenOffer>[],
);

/// Las ofertas del buzón, más las de prueba.
final koenAllOffersProvider = Provider<List<KoenOffer>>(
  (ref) => [
    ...ref.watch(koenDemoOffersProvider),
    ...?ref.watch(koenOffersProvider).valueOrNull,
  ],
);

/// Ofertas sin responder: la insignia del canal del parque.
final pendingKoenOffersProvider = Provider<int>(
  (ref) => ref.watch(koenAllOffersProvider).length,
);

/// Al abrir, quita los cuidados a medias con quien ya no es amigo. Se mira
/// desde la app.
final koenCareTidyProvider = Provider<void>((ref) {
  final ready =
      ref.watch(friendsProvider.select((f) => f.loaded)) &&
      ref.watch(tamasProvider.select((t) => t.loaded));
  if (!ready) return;
  final friends = ref.watch(
    friendsProvider.select(
      (f) => {for (final x in f.friends) x.accountId}.join(','),
    ),
  );
  final shares = ref.watch(
    tamasProvider.select(
      (t) => [
        for (final x in t.tamas)
          if (x.carer != null) '${x.id}:${x.carer}',
        for (final x in t.cared) '${x.id}:${x.creator}',
      ].join(','),
    ),
  );
  if (shares.isEmpty) return;
  unawaited(
    ref.read(tamasProvider.notifier).tidyShares(friends.split(',').toSet()),
  );
});

/// Los dúos de la cuenta (lo que comparten se lee al abrir el parque y la
/// casita).
final koenDuosStateProvider =
    StateNotifierProvider<KoenDuosController, KoenDuosState>((ref) {
      ref.watch(sessionProvider.select((s) => s.accountId));
      return KoenDuosController(
        backend: ref.watch(backendProvider),
        session: ref.watch(sessionProvider.notifier),
        coinsOf: () => ref.read(coinsProvider),
        ticketsOf: (kind) => ref.read(gachaProvider).ticketsOf(kind),
        owns: (key) => ref.read(gachaProvider).owns(key),
      );
    });

/// Los dúos: los amigos con los que se cuida a medias un Tama de cada uno,
/// más el del parque de prueba.
final koenDuosProvider = Provider<List<KoenDuo>>((ref) {
  final me = ref.watch(sessionProvider.select((s) => s.accountId));
  final tamas = ref.watch(tamasProvider);
  final duos = ref.watch(koenDuosStateProvider);
  final out = [
    for (final MapEntry(key: friend, value: (mine, theirs)) in koenDuoTamas(
      me,
      tamas.tamas,
      tamas.cared,
    ).entries)
      KoenDuo(
        me: me,
        friend: friend,
        mine: mine,
        theirs: theirs,
        data: duos.data[friend] ?? const KoenDuoData(),
      ),
  ];
  final demoMine = tamas.tamas.where((t) => t.id == duos.demoMine).firstOrNull;
  final demoTheirs = [
    for (final t in tamas.cared)
      if (t.creator == duos.demoFriend) t,
  ];
  if (demoMine != null &&
      demoTheirs.isNotEmpty &&
      !out.any((d) => d.friend == duos.demoFriend)) {
    out.add(
      KoenDuo(
        me: me,
        friend: duos.demoFriend!,
        mine: [demoMine],
        theirs: demoTheirs,
        data: duos.data[duos.demoFriend] ?? const KoenDuoData(),
        demo: true,
      ),
    );
  }
  return out;
});

/// El dúo de [friend], si lo hay.
final koenDuoWithProvider = Provider.family<KoenDuo?, String>(
  (ref, friend) =>
      ref.watch(koenDuosProvider).where((d) => d.friend == friend).firstOrNull,
);

/// El dúo en cuya casita está [tamaId], si lo hay.
KoenDuo? koenDuoOfTama(List<KoenDuo> duos, String tamaId) =>
    duos.where((d) => d.tamaIds.contains(tamaId)).firstOrNull;

bool _demoCareClaimed = false;

/// Cobra las monedas de cuidar a medias si [tama] es compartido y hoy ya ha
/// comido y le han hecho un mimo. Una vez al día por cuenta. Devuelve lo
/// cobrado.
Future<int> claimKoenCare(WidgetRef ref, Tama tama) async {
  if (!tama.shared) return 0;
  // El del parque de prueba enseña el aviso una vez, sin cobrar nada.
  if (tama.id.startsWith('-demo')) {
    if (_demoCareClaimed || !koenCareDone(tama, RewardsState.today())) return 0;
    _demoCareClaimed = true;
    return koenCareCoins;
  }
  final rewards = ref.read(rewardsProvider);
  if (!rewards.loaded || rewards.earnedToday(koenCareGame) > 0) return 0;
  if (!koenCareDone(tama, RewardsState.today())) return 0;
  final out = await ref
      .read(rewardsProvider.notifier)
      .claim(
        game: koenCareGame,
        amount: koenCareCoins,
        extra: {'tama': tama.id},
      );
  return out.status == RewardStatus.granted ? out.coins : 0;
}

/// El pueblo de Hatarakitama de otra cuenta (o de la propia), para
/// visitarlo: una lectura puntual de `hataraki`, sin conexion en tiempo real.
/// `null` si no ha jugado nunca.
final hatarakiVisitProvider = FutureProvider.autoDispose
    .family<HatarakiVisit?, String>((ref, accountId) async {
      final session = ref.read(sessionProvider.notifier);
      final raw = await ref
          .read(backendProvider)
          .read(
            '/users/$accountId/hataraki',
            idToken: await session.freshToken(),
          );
      if (raw is! Map) return null;
      return HatarakiVisit(
        game: HState.fromJson(raw, DateTime.now().millisecondsSinceEpoch),
        tamas: hatarakiVisitTamas(raw['visit'], accountId),
      );
    });

/// Mantiene al dia la musica del menu cuando es una cancion de Tamakoro: la
/// vuelve a renderizar si cambia la cancion o la voz de alguien del coro.
final koroMenuMusicProvider = Provider<void>((ref) {
  final library = ref.watch(
    musicLibraryProvider.select((m) => (loaded: m.loaded, track: m.menuTrack)),
  );
  if (!library.loaded) return;
  // Kōbō local: si una pista ext: gobierna este dispositivo, su archivo lo
  // gestiona el Content Registry. Tamakoro no debe borrar ese menuFile solo
  // porque el menuTrack remoto de la cuenta sea una pista nativa.
  final localMusic = ref.watch(preferencesProvider.select((p) => p.musicTrack));
  if (localMusic.startsWith('ext:')) return;
  final slot = koroSlotOfTrack(library.track);
  if (slot == null) {
    unawaited(applyKoroMenuMusic(null, const <Tama>[]));
    return;
  }
  final koro = ref.watch(
    koroProvider.select((k) => (loaded: k.loaded, song: k.songs[slot])),
  );
  final song = koro.song;
  // Solo las voces del coro: dar de comer a un Tama no vuelve a renderizar.
  final voices = ref.watch(
    tamasProvider.select(
      (t) => t.loaded && song != null
          ? koroVoices(song, t.tamas)
                .map(
                  (v) => v == null
                      ? '-'
                      : '${v.pitch}.${v.tempo}.${v.timbre.index}',
                )
                .join(',')
          : null,
    ),
  );
  if (!koro.loaded || voices == null) return;
  unawaited(applyKoroMenuMusic(song, ref.read(tamasProvider).tamas));
});
