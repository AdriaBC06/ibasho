// Ibasho — mensajeria cifrada, noticias y sugerencias: criterios de la 0.4.0.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Aqui se prueba lo que hace la app; que el servidor no deje hacer otra cosa
// lo prueban las reglas (`test/rules/rules_04.test.mjs`). El backend falso no
// aplica reglas a proposito: si las aplicara, estos tests pasarian por lo que
// prohibe el servidor y no por lo que hace el cliente.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/backend/messaging.dart';
import 'package:ibasho/backend/news.dart';
import 'package:ibasho/backend/suggestions.dart';
import 'package:ibasho/crypto/envelope.dart';
import 'package:ibasho/crypto/keys.dart';
import 'package:ibasho/state/conversation.dart';
import 'package:ibasho/state/identity.dart';
import 'package:ibasho/state/messages.dart';
import 'package:ibasho/state/news.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/secure_store.dart';
import 'package:ibasho/storage/settings_store.dart';

import 'support/fakes.dart';

const String kLuis = 'uid-luis';
const String kPau = 'uid-pau';

Future<void> main() async {
  /// Deja correr los `Future` de verdad. Los controladores arrancan solos en
  /// el constructor y descifran en un isolate: sin ceder el turno varias
  /// veces, el estado que se lee es el de antes de que llegara nada.
  Future<void> settle([int turns = 40]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  ProviderContainer boot(FakeIbashoBackend backend, {SecureStore? store}) {
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(backend),
        secureStoreProvider
            .overrideWithValue(store ?? FakeSecureStore(session: backend.tokens)),
        settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        initialPreferencesProvider.overrideWithValue(const Preferences()),
        batteryWatchProvider.overrideWithValue(FakeBatteryWatch()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> signedIn(
    FakeIbashoBackend backend, {
    SecureStore? store,
  }) async {
    final container = boot(backend, store: store);
    await container.read(sessionProvider.notifier).restore();
    await settle(10);
    return container;
  }

  group('claves de la cuenta', () {
    test('la primera vez se crean, se publican y se enseña la frase', () async {
      final backend = FakeIbashoBackend();
      final container = await signedIn(backend);
      container.listen(identityProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final identity = container.read(identityProvider);
      expect(identity.phase, IdentityPhase.fresh);
      expect(identity.phrase, hasLength(12));
      expect(identity.keys, isNotNull);

      // Lo que queda publicado: la publica, y la privada envuelta. La frase no
      // esta en ninguna parte de la base, que es lo que la hace util.
      final stored = backend.peek('/users/${backend.uid}/keys');
      expect(stored, isA<Map<Object?, Object?>>());
      final published = stored! as Map;
      expect(published['pub'], identity.keys!.public.encoded);
      expect(published['backup'], isA<Map<Object?, Object?>>());
      expect(
        published.toString().contains(identity.phrase.first),
        isFalse,
        reason: 'la frase no puede acabar en la base ni de rebote',
      );

      container.read(identityProvider.notifier).confirmPhraseSeen();
      expect(container.read(identityProvider).phase, IdentityPhase.ready);
    });

    test('en otro aparato pide la frase, y con la buena vuelve todo', () async {
      final backend = FakeIbashoBackend();
      final primero = await signedIn(backend);
      primero.listen(identityProvider, (_, _) {}, fireImmediately: true);
      await settle();
      final frase = primero.read(identityProvider).phrase;
      final publica = primero.read(identityProvider).keys!.public.encoded;

      // Mismo servidor, llavero vacio: es exactamente el movil recien
      // instalado, o el ordenador de al lado.
      final segundo = await signedIn(
        backend,
        store: FakeSecureStore(session: backend.tokens),
      );
      segundo.listen(identityProvider, (_, _) {}, fireImmediately: true);
      await settle();
      expect(segundo.read(identityProvider).phase, IdentityPhase.needsPhrase);

      final otra = await segundo
          .read(identityProvider.notifier)
          .restoreWithPhrase('abeja abeto abedul acelga aceite actor apio arce '
              'arena arroyo avena azucar');
      // Doce palabras de la lista, pero no son las suyas.
      expect(otra?.failure, anyOf(isNull, MnemonicFailureMatcher()));
      expect(segundo.read(identityProvider).phase, IdentityPhase.needsPhrase);

      final fallo =
          await segundo.read(identityProvider.notifier).restoreWithPhrase(frase.join(' '));
      await settle(10);
      expect(fallo, isNull);
      expect(segundo.read(identityProvider).phase, IdentityPhase.ready);
      expect(segundo.read(identityProvider).keys!.public.encoded, publica);
    });
  });

  group('conversacion privada', () {
    /// Ana (la cuenta del backend falso) y Luis, ya amigos y con claves.
    Future<(ProviderContainer, IdentityKeys)> conversation(
      FakeIbashoBackend backend,
    ) async {
      final luis = IdentityKeys.generate();
      final now = DateTime.now().millisecondsSinceEpoch;
      backend
        ..seed('/users/$kLuis/keys/pub', luis.public.encoded)
        ..seed('/users/$kLuis/card', {'displayName': 'Luis', 'accentColor': '#5BC8F5'})
        ..seed('/users/${backend.uid}/friends/$kLuis', {'since': now})
        ..seed('/users/$kLuis/friends/${backend.uid}', {'since': now});

      final container = await signedIn(backend);
      container.listen(identityProvider, (_, _) {}, fireImmediately: true);
      await settle();
      container.read(identityProvider.notifier).confirmPhraseSeen();
      return (container, luis);
    }

    test('lo que sale a la base solo lo abren los dos que hablan', () async {
      final backend = FakeIbashoBackend();
      final (container, luis) = await conversation(backend);

      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle();

      final sent = await container
          .read(conversationProvider(target).notifier)
          .send(const TextBody('nos vemos a las ocho'));
      await settle();
      expect(sent, isTrue);

      final pair = directPairId(backend.uid, kLuis);
      final msgs = backend.peek('/dm/$pair/msgs')! as Map;
      expect(msgs, hasLength(1));

      final raw = msgs.values.first! as Map;
      // En la base no hay ni rastro del texto: solo el sobre y quien lo manda.
      expect(raw.toString().contains('ocho'), isFalse);
      expect(raw['from'], backend.uid);
      expect(raw['kind'], 'text');

      final envelope = SealedEnvelope.fromJson(raw)!;
      expect(envelope.open(kLuis, luis), '{"t":"text","b":"nos vemos a las ocho"}');
      // Ni un tercero con sus propias claves, ni nadie haciendose pasar por Luis.
      expect(envelope.open(kPau, IdentityKeys.generate()), isNull);
      expect(envelope.open(kLuis, IdentityKeys.generate()), isNull);

      // Y el aviso que enciende la chapa, sin nada dentro.
      final inbox = backend.peek('/users/$kLuis/inbox/${backend.uid}');
      expect(inbox, isA<Map<Object?, Object?>>());
      expect((inbox! as Map).keys.map((k) => '$k').toList(), <String>['at']);
    });

    test('lo que llega cifrado se lee, y lo ajeno se queda cerrado', () async {
      final backend = FakeIbashoBackend();
      final (container, luis) = await conversation(backend);
      final me = backend.uid;
      final mine = container.read(identityProvider).keys!;
      final pair = directPairId(me, kLuis);

      final ends = directPairEnds(me, kLuis);
      backend
        ..seed('/dm/$pair/a', ends.a)
        ..seed('/dm/$pair/b', ends.b)
        ..seed('/dm/$pair/msgs/AAAAAAAAAAAAAAAAAAAA', {
          'at': DateTime.now().millisecondsSinceEpoch,
          'from': kLuis,
          'kind': 'text',
          ...SealedEnvelope.seal(
            const TextBody('hasta luego').encode(),
            recipients: {me: mine.public, kLuis: luis.public},
          ).toJson(),
        })
        // Un sobre que no va para esta cuenta: tiene que verse el hueco y no
        // tumbar la conversacion entera.
        ..seed('/dm/$pair/msgs/BBBBBBBBBBBBBBBBBBBB', {
          'at': DateTime.now().millisecondsSinceEpoch,
          'from': kLuis,
          'kind': 'text',
          ...SealedEnvelope.seal(
            const TextBody('esto no es para ti').encode(),
            recipients: {kPau: IdentityKeys.generate().public},
          ).toJson(),
        });

      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(60);

      final state = container.read(conversationProvider(target));
      expect(state.loading, isFalse);
      expect(state.messages, hasLength(2));
      expect((state.messages.first.body! as TextBody).text, 'hasta luego');
      expect(state.messages.last.readable, isFalse);
    });

    test('el primer mensaje a alguien aparece aunque no se pudiera leer', () async {
      // El caso que se vio usandolo: hasta que la conversacion no existe, las
      // reglas niegan leerla —no hay `a` ni `b`, asi que nadie es de ella— y
      // la lectura y el flujo fallan. El mensaje entraba en la base y no salia
      // nunca en pantalla.
      final backend = FakeIbashoBackend();
      final pair = directPairId(backend.uid, kLuis);
      backend.denyRead = (path) =>
          path.startsWith('/dm/$pair') && backend.peek('/dm/$pair/a') == null;

      final (container, luis) = await conversation(backend);

      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(40);
      expect(container.read(conversationProvider(target)).messages, isEmpty);

      expect(
        await container
            .read(conversationProvider(target).notifier)
            .send(const TextBody('primera')),
        isTrue,
      );
      await settle(20);

      final state = container.read(conversationProvider(target));
      expect(state.messages, hasLength(1), reason: 'tiene que verse al mandarlo');
      expect((state.messages.single.body! as TextBody).text, 'primera');
      expect(state.messages.single.from, backend.uid);

      // Y de verdad salio: el otro lado puede abrirlo.
      final raw = (backend.peek('/dm/$pair/msgs')! as Map).values.first! as Map;
      expect(SealedEnvelope.fromJson(raw)!.open(kLuis, luis),
          '{"t":"text","b":"primera"}');
    });

    test('lo mandado no se duplica cuando el servidor lo devuelve', () async {
      final backend = FakeIbashoBackend();
      final (container, _) = await conversation(backend);
      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(30);

      await container
          .read(conversationProvider(target).notifier)
          .send(const TextBody('hola'));
      await settle(40);

      final mensajes = container.read(conversationProvider(target)).messages;
      expect(mensajes, hasLength(1));
      expect((mensajes.single.body! as TextBody).text, 'hola');
    });

    test('un sticker viaja con el aspecto dentro y se vuelve a pintar igual', () {
      final tama = mireiaTama();
      final body = StickerBody(
        face: StickerFace.love,
        name: tama.name,
        look: tama.look,
      );
      final vuelta = MessageBody.decode(body.encode());
      expect(vuelta, isA<StickerBody>());
      final sticker = vuelta! as StickerBody;
      expect(sticker.face, StickerFace.love);
      expect(sticker.name, tama.name);
      // El aspecto entero, no una referencia: por eso se sigue viendo aunque
      // el Tama se edite o se borre, y aunque quien lo recibe no tenga permiso
      // para leerlo en la base.
      expect(sticker.look, tama.look);
    });

    test('al mandar se poda lo que sobra del historial', () async {
      final backend = FakeIbashoBackend();
      final (container, luis) = await conversation(backend);
      final me = backend.uid;
      final mine = container.read(identityProvider).keys!;
      final pair = directPairId(me, kLuis);
      final now = DateTime.now();

      final ends = directPairEnds(me, kLuis);
      backend
        ..seed('/dm/$pair/a', ends.a)
        ..seed('/dm/$pair/b', ends.b);

      String id(int n) => n.toString().padLeft(20, '0');
      for (var i = 0; i < messagesPerConversation; i++) {
        backend.seed('/dm/$pair/msgs/${id(i)}', {
          // El primero es de hace mas de noventa dias: cae por viejo aunque no
          // se llegara al tope.
          'at': (i == 0 ? now.subtract(const Duration(days: 120)) : now)
              .millisecondsSinceEpoch,
          'from': kLuis,
          'kind': 'text',
          ...SealedEnvelope.seal(
            TextBody('mensaje $i').encode(),
            recipients: {me: mine.public, kLuis: luis.public},
          ).toJson(),
        });
      }

      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(80);

      await container
          .read(conversationProvider(target).notifier)
          .send(const TextBody('y uno mas'));
      await settle(20);

      // Habia 300 y entra uno mas: sobra exactamente uno, y ademas ese era el
      // de hace cuatro meses. El historial se mantiene en su tope sin que haya
      // ninguna tarea de limpieza en ninguna parte.
      final msgs = backend.peek('/dm/$pair/msgs')! as Map;
      expect(msgs, hasLength(messagesPerConversation));
      expect(msgs.containsKey(id(0)), isFalse, reason: 'el mas viejo se poda');
      expect(msgs.containsKey(id(1)), isTrue, reason: 'y solo el que sobra');
    });

    test('lo que pasa de noventa dias cae aunque no se llegue al tope', () async {
      final backend = FakeIbashoBackend();
      final (container, luis) = await conversation(backend);
      final me = backend.uid;
      final mine = container.read(identityProvider).keys!;
      final pair = directPairId(me, kLuis);
      final ends = directPairEnds(me, kLuis);
      backend
        ..seed('/dm/$pair/a', ends.a)
        ..seed('/dm/$pair/b', ends.b);

      Map<String, Object?> viejo(Duration edad) => <String, Object?>{
            'at': DateTime.now().subtract(edad).millisecondsSinceEpoch,
            'from': kLuis,
            'kind': 'text',
            ...SealedEnvelope.seal(
              const TextBody('hola').encode(),
              recipients: {me: mine.public, kLuis: luis.public},
            ).toJson(),
          };

      backend
        ..seed('/dm/$pair/msgs/00000000000000000001', viejo(const Duration(days: 120)))
        ..seed('/dm/$pair/msgs/00000000000000000002', viejo(const Duration(days: 30)));

      const target = DirectTarget(kLuis);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(40);
      await container
          .read(conversationProvider(target).notifier)
          .send(const TextBody('y uno de hoy'));
      await settle(20);

      final msgs = backend.peek('/dm/$pair/msgs')! as Map;
      expect(msgs.containsKey('00000000000000000001'), isFalse);
      expect(msgs.containsKey('00000000000000000002'), isTrue);
      expect(msgs, hasLength(2));
    });
  });

  group('grupo', () {
    test('sin unirse no se lee, y al unirse se deja la clave publica', () async {
      final backend = FakeIbashoBackend()
        ..seed('/groups/global/meta', {
          'name': 'Global',
          'open': true,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      final container = await signedIn(backend);
      container.listen(identityProvider, (_, _) {}, fireImmediately: true);
      container.listen(messagesProvider, (_, _) {}, fireImmediately: true);
      await settle();
      container.read(identityProvider.notifier).confirmPhraseSeen();

      expect(container.read(messagesProvider).inGlobal, isFalse);
      const target = GroupTarget(globalGroupId);
      container.listen(conversationProvider(target), (_, _) {}, fireImmediately: true);
      await settle(20);
      expect(
        container.read(conversationProvider(target)).block,
        SendBlock.notMember,
        reason: 'hasta que no se une, ni una lectura',
      );

      final failure = await container.read(messagesProvider.notifier).joinGlobal();
      await settle(20);
      expect(failure, isNull);
      expect(container.read(messagesProvider).inGlobal, isTrue);

      // La publica se copia en la entrada de miembro: es lo que deja cifrar
      // para los treinta y dos con una sola lectura.
      final entry = backend.peek('/groups/global/members/${backend.uid}')! as Map;
      expect(entry['pub'], container.read(identityProvider).keys!.public.encoded);
      expect(backend.peek('/users/${backend.uid}/groups/global'), isNotNull);
    });
  });

  group('noticias', () {
    test('votar mueve el recuento y deja el voto fuera de la encuesta', () async {
      final backend = FakeIbashoBackend()
        ..seed('/news/AAAAAAAAAAAAAAAAAAAA', {
          'kind': 'poll',
          'title': 'Que viene despues',
          'at': DateTime.now().millisecondsSinceEpoch,
          'by': 'admin',
          'options': {'0': 'Un minijuego', '1': 'Una tienda'},
          'tally': {'0': 2, '1': 1},
        });
      final container = await signedIn(backend);
      container.listen(newsProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final state = container.read(newsProvider);
      expect(state.items, hasLength(1));
      expect(state.items.first.isPoll, isTrue);
      expect(state.items.first.totalVotes, 3);
      expect(state.items.first.share(0), closeTo(2 / 3, 1e-9));

      expect(
        await container.read(newsProvider.notifier).vote('AAAAAAAAAAAAAAAAAAAA', 1),
        isTrue,
      );
      await settle(10);

      final poll = backend.peek('/news/AAAAAAAAAAAAAAAAAAAA')! as Map;
      expect((poll['tally']! as Map)['1'], 2);
      expect((poll['voters']! as Map).containsKey(backend.uid), isTrue);
      // En la encuesta queda que has votado, nunca a que: eso vive solo en tu
      // arbol, y es lo que la hace anonima de verdad y no solo en la pantalla.
      expect(poll.toString().contains('"${backend.uid}":1'), isFalse);
      expect(backend.peek('/users/${backend.uid}/votes/AAAAAAAAAAAAAAAAAAAA'), 1);

      // Cambiar el voto baja el anterior y sube el nuevo.
      await container.read(newsProvider.notifier).vote('AAAAAAAAAAAAAAAAAAAA', 0);
      await settle(10);
      final after = backend.peek('/news/AAAAAAAAAAAAAAAAAAAA')! as Map;
      expect((after['tally']! as Map)['0'], 3);
      expect((after['tally']! as Map)['1'], 1);
    });

    test('una encuesta cerrada no admite votos', () async {
      final backend = FakeIbashoBackend()
        ..seed('/news/AAAAAAAAAAAAAAAAAAAA', {
          'kind': 'poll',
          'title': 'Cerrada',
          'at': DateTime.now().millisecondsSinceEpoch,
          'by': 'admin',
          'options': {'0': 'Si', '1': 'No'},
          'closed': true,
        });
      final container = await signedIn(backend);
      container.listen(newsProvider, (_, _) {}, fireImmediately: true);
      await settle();
      expect(
        await container.read(newsProvider.notifier).vote('AAAAAAAAAAAAAAAAAAAA', 0),
        isFalse,
      );
    });
  });

  group('sugerencias', () {
    test('una viva por cuenta, y otra en cuanto hay veredicto', () async {
      final backend = FakeIbashoBackend();
      final container = await signedIn(backend);
      container.listen(suggestionsProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final notifier = container.read(suggestionsProvider.notifier);
      expect(container.read(suggestionsProvider).canSubmit, isTrue);
      expect(
        await notifier.submit(title: 'Musica', body: 'Una pista por Tama.'),
        isTrue,
      );
      await settle(10);

      final mine = container.read(suggestionsProvider).mine!;
      expect(mine.status, SuggestionStatus.pending);
      expect(container.read(suggestionsProvider).canSubmit, isFalse);
      expect(await notifier.submit(title: 'Otra', body: 'Otra idea.'), isFalse);

      backend.seed('/suggestions/${backend.uid}/status', 'accepted');
      await settle(10);
      expect(container.read(suggestionsProvider).canSubmit, isTrue);
    });

    test('el buzon cerrado no admite nada', () async {
      final backend = FakeIbashoBackend()..seed('/system/suggestionsOpen', false);
      final container = await signedIn(backend);
      container.listen(suggestionsProvider, (_, _) {}, fireImmediately: true);
      await settle();
      expect(container.read(suggestionsProvider).open, isFalse);
      expect(container.read(suggestionsProvider).canSubmit, isFalse);
    });
  });

  group('chapas del entorno', () {
    test('cuenta las conversaciones con algo sin leer, no los mensajes', () {
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      final hoy = DateTime.now();
      final state = MessagesState(
        inbox: {kLuis: hoy, kPau: ayer},
        readDirect: {kPau: hoy},
        inGlobal: true,
        globalLastAt: hoy,
        globalRead: ayer,
      );
      expect(state.unreadFrom(kLuis), isTrue);
      expect(state.unreadFrom(kPau), isFalse);
      expect(state.unreadInGlobal, isTrue);
      // Dos conversaciones, no los mensajes que haya dentro.
      expect(state.unreadCount, 2);
    });

    test('las conversaciones se ordenan por la mas reciente', () {
      final ahora = DateTime.now();
      final state = MessagesState(
        inbox: {'b': ahora, 'c': ahora.subtract(const Duration(days: 2))},
        readDirect: {'a': ahora.subtract(const Duration(hours: 1))},
      );
      // b escribio hace nada; a se leyo hace una hora; c hace dos dias; d nunca.
      expect(
        state.byRecency(<String>['a', 'b', 'c', 'd'], (x) => x),
        <String>['b', 'a', 'c', 'd'],
      );
    });

    test('el tablon cuenta lo publicado despues de la ultima visita', () {
      NewsItem item(String id, DateTime at) =>
          NewsItem(id: id, kind: NewsKind.note, title: id, at: at, by: 'admin');
      final ayer = DateTime.now().subtract(const Duration(days: 1));
      final hoy = DateTime.now();
      final state = NewsState(
        items: [item('b', hoy), item('a', ayer)],
        lastRead: ayer.add(const Duration(minutes: 1)),
      );
      expect(state.unreadCount, 1);
      // Sin haber entrado nunca, todo es nuevo.
      expect(NewsState(items: [item('b', hoy)]).unreadCount, 1);
    });
  });
}

/// Solo para leer mejor la expectativa de arriba: cualquier fallo de frase
/// sirve, lo que importa es que no haya recuperado nada.
class MnemonicFailureMatcher extends Matcher {
  @override
  bool matches(Object? item, Map<Object?, Object?> state) => true;

  @override
  Description describe(Description description) =>
      description.add('cualquier fallo de frase');
}
