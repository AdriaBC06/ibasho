// Ibasho — una conversacion abierta: descifrar, mandar y podar.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/messaging.dart';
import '../backend/models.dart';
import '../backend/push_id.dart';
import '../crypto/worker.dart';
import '../crypto/keys.dart';
import 'messages.dart';
import 'session.dart';

/// Cuantos mensajes se descifran de una tanda.
///
/// Abrir un sobre cuesta unos 9 ms y una conversacion llena son 300: de golpe
/// serian casi tres segundos. Se empieza por los ultimos —lo que se esta
/// mirando— y el resto va llegando por tandas mientras se sube.
const int _batch = 30;

/// Por que no se puede escribir aqui.
enum SendBlock {
  /// Esta cuenta aun no tiene claves en este aparato.
  noKeys,

  /// La otra persona no ha entrado nunca desde que hay cifrado, asi que no
  /// tiene clave publica y no hay a quien cifrarle.
  otherHasNoKeys,
}

@immutable
class ConversationState {
  const ConversationState({
    this.messages = const <Message>[],
    this.loading = true,
    this.decrypting = false,
    this.sending = false,
    this.block,
    this.failed = false,
  });

  /// Del mas viejo al mas nuevo, que es como se lee.
  final List<Message> messages;

  /// Todavia no ha llegado la primera tanda.
  final bool loading;

  /// Quedan mensajes viejos por abrir.
  final bool decrypting;

  final bool sending;

  /// Si no se puede escribir, por que.
  final SendBlock? block;

  /// La carga no llego al servidor.
  final bool failed;

  bool get canSend => block == null && !sending;

  DateTime? get lastAt => messages.isEmpty ? null : messages.last.at;

  ConversationState copyWith({
    List<Message>? messages,
    bool? loading,
    bool? decrypting,
    bool? sending,
    SendBlock? block,
    bool clearBlock = false,
    bool? failed,
  }) =>
      ConversationState(
        messages: messages ?? this.messages,
        loading: loading ?? this.loading,
        decrypting: decrypting ?? this.decrypting,
        sending: sending ?? this.sending,
        block: clearBlock ? null : (block ?? this.block),
        failed: failed ?? this.failed,
      );
}

/// Una conversacion: la de un amigo o la del grupo.
///
/// Lo que llega de la base son sobres cerrados. Aqui se abren —en un isolate,
/// por tandas y empezando por los ultimos— y lo que sale no se guarda en
/// ningun sitio: al cerrar el canal se va con el controlador.
class ConversationController extends StateNotifier<ConversationState> {
  ConversationController({
    required IbashoBackend backend,
    required SessionController session,
    required IdentityKeys? keys,
    required this.target,
  })  : _backend = backend,
        _session = session,
        _keys = keys,
        super(const ConversationState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;

  /// Las claves de esta cuenta, o `null` si aun no estan.
  final IdentityKeys? _keys;

  final ConversationTarget target;

  StreamSubscription<DatabaseEvent>? _watch;
  Object? _tree;

  /// Si el flujo en tiempo real esta escuchando de verdad.
  ///
  /// Hace falta saberlo porque en una conversacion que aun no existe las
  /// reglas **deniegan la lectura**: `/dm/<par>` no tiene `a` ni `b` hasta que
  /// se manda el primer mensaje, y sin ellos nadie es de la conversacion. El
  /// flujo se vuelve a levantar en cuanto hay algo que leer.
  bool _watching = false;

  /// Lo mandado desde aqui que el servidor todavia no ha devuelto.
  ///
  /// Se pinta en cuanto sale, sin esperar al eco: el viaje de ida y vuelta se
  /// nota, y un mensaje que tarda en aparecer parece un mensaje perdido.
  final Map<String, Message> _sent = {};

  /// Sobres por abrir, de los mas nuevos a los mas viejos.
  final List<StoredMessage> _pending = [];

  /// Lo ya descifrado, por id: al llegar un mensaje nuevo no se vuelve a abrir
  /// todo lo anterior.
  final Map<String, MessageBody?> _opened = {};

  /// La clave publica de la otra persona, leida una vez.
  String? _otherKey;

  String get _me => _session.state.accountId;

  String get _root => switch (target) {
        DirectTarget(:final accountId) => '/dm/${directPairId(_me, accountId)}',
      };

  @override
  void dispose() {
    unawaited(_watch?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final block = await _checkBlock();
    if (!mounted) return;
    state = state.copyWith(block: block, clearBlock: block == null);

    try {
      final token = await _session.freshToken();
      _tree = await _backend.read('$_root/msgs', idToken: token);
    } catch (e) {
      // Que falle no es un error que contar: una conversacion que todavia no
      // existe no se puede leer, y es el caso de la primera vez que se le
      // escribe a alguien. Se sigue como si estuviera vacia.
      debugPrint('Ibasho: la conversacion aun no se puede leer ($e)');
      _tree = null;
    }
    if (!mounted) return;

    await _refresh(first: true);
    if (!mounted) return;
    _listen();
  }

  /// Abre el flujo en tiempo real. Se puede llamar mas de una vez.
  void _listen() {
    if (_watching) return;
    _watching = true;
    _watch = _backend.watch('$_root/msgs', token: _session.freshToken).listen((e) {
      _tree = applyDatabaseEvent(_tree, e);
      unawaited(_refresh());
    }, onError: (Object e) {
      debugPrint('Ibasho: stream de la conversacion ($e)');
      _watching = false;
      unawaited(_watch?.cancel());
      _watch = null;
    });
  }

  /// Vuelve a mirar el arbol local y abre lo que haga falta.
  Future<void> _refresh({bool first = false}) async {
    final stored = _stored();
    _pending
      ..clear()
      ..addAll(stored.reversed.where((m) => !_opened.containsKey(m.id)));

    if (first) {
      await _openMore();
      if (!mounted) return;
      state = state.copyWith(loading: false, messages: _assemble(stored));
      // Lo que quede viejo se abre solo, sin bloquear nada.
      unawaited(_drain());
    } else {
      await _openMore();
      if (mounted) state = state.copyWith(messages: _assemble(stored));
    }
  }

  /// Abre una tanda de los que quedan.
  Future<void> _openMore() async {
    final keys = _keys;
    if (keys == null || _pending.isEmpty) return;
    final tanda = _pending.take(_batch).toList(growable: false);
    _pending.removeRange(0, tanda.length);

    final plain = await CryptoWorker.open(
      envelopes: [for (final m in tanda) m.envelope.toJson()],
      account: _me,
      privateKey: keys.privateBytes,
    );
    for (var i = 0; i < tanda.length; i++) {
      final text = plain[i];
      _opened[tanda[i].id] = text == null ? null : MessageBody.decode(text);
    }
  }

  /// Sigue abriendo hasta que no quede nada, un respiro entre tandas.
  Future<void> _drain() async {
    while (mounted && _pending.isNotEmpty) {
      if (mounted) state = state.copyWith(decrypting: true);
      await _openMore();
      if (!mounted) return;
      state = state.copyWith(messages: _assemble(_stored()), decrypting: false);
    }
  }

  List<StoredMessage> _stored() {
    final raw = _tree;
    if (raw is! Map) return const <StoredMessage>[];
    final out = <StoredMessage>[];
    for (final e in raw.entries) {
      final m = StoredMessage.fromJson('${e.key}', e.value);
      if (m != null) out.add(m);
    }
    // Los ids de push ya ordenan por tiempo: no hace falta mirar `at`, que
    // ademas lo pone el servidor y podria empatar.
    out.sort((a, b) => a.id.compareTo(b.id));
    return out;
  }

  List<Message> _assemble(List<StoredMessage> stored) {
    final out = <Message>[
      for (final m in stored)
        Message(id: m.id, at: m.at, from: m.from, kind: m.kind, body: _opened[m.id]),
    ];
    // Lo que ya ha vuelto del servidor deja de estar pendiente.
    _sent.removeWhere((id, _) => stored.any((m) => m.id == id));
    if (_sent.isNotEmpty) {
      out.addAll(_sent.values);
      // Los ids de push ordenan por tiempo, asi que lo recien mandado cae
      // solo en su sitio: al final.
      out.sort((a, b) => a.id.compareTo(b.id));
    }
    return List<Message>.unmodifiable(out);
  }

  Future<SendBlock?> _checkBlock() async {
    if (_keys == null) return SendBlock.noKeys;
    switch (target) {
      case DirectTarget(:final accountId):
        try {
          final token = await _session.freshToken();
          final raw =
              await _backend.read('/users/$accountId/keys/pub', idToken: token);
          if (raw is! String || raw.isEmpty) return SendBlock.otherHasNoKeys;
          _otherKey = raw;
          return null;
        } catch (e) {
          debugPrint('Ibasho: no se ha podido leer la clave del otro ($e)');
          return SendBlock.otherHasNoKeys;
        }
    }
  }

  /// Manda un mensaje. `false` si no ha salido.
  ///
  /// Es una sola escritura multi-ruta: el mensaje, el aviso en el arbol de
  /// quien lo recibe y la poda de lo viejo. O entra todo o no entra nada.
  Future<bool> send(MessageBody body) async {
    if (!state.canSend) return false;
    final keys = _keys;
    if (keys == null) return false;

    final recipients = _recipients();
    if (recipients.isEmpty) return false;

    state = state.copyWith(sending: true, failed: false);
    try {
      final envelope = await CryptoWorker.seal(
        plaintext: body.encode(),
        recipients: recipients,
      );
      final id = generatePushId();
      final writes = <String, Object?>{
        ..._messageWrite(id, body.kind, envelope),
        ..._pruneWrites(),
      };
      final token = await _session.freshToken();
      await _backend.merge('/', writes, idToken: token);
      if (!mounted) return true;

      // Se pinta ya, sin esperar a que el servidor lo devuelva por el flujo.
      // Ademas es lo unico que lo hace visible la primera vez que se escribe a
      // alguien: hasta que existe la conversacion, las reglas no dejan leerla.
      _opened[id] = body;
      _sent[id] = Message(
        id: id,
        at: DateTime.now(),
        from: _me,
        kind: body.kind,
        body: body,
      );
      // Y con la conversacion ya creada, el flujo por fin puede abrirse.
      _listen();
      state = state.copyWith(sending: false, messages: _assemble(_stored()));
      return true;
    } catch (e) {
      debugPrint('Ibasho: el mensaje no ha salido ($e)');
      if (mounted) state = state.copyWith(sending: false, failed: true);
      return false;
    }
  }

  /// Borra un mensaje. Desaparece para todos los que estan en la conversacion:
  /// no queda una copia en el otro lado.
  Future<bool> remove(String messageId) async {
    try {
      final token = await _session.freshToken();
      await _backend.remove('$_root/msgs/$messageId', idToken: token);
      _opened.remove(messageId);
      if (_sent.remove(messageId) != null && mounted) {
        state = state.copyWith(messages: _assemble(_stored()));
      }
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido borrar el mensaje ($e)');
      return false;
    }
  }

  /// A quien hay que cifrarle: siempre incluye a quien escribe, o no podria
  /// releer lo que acaba de mandar.
  Map<String, String> _recipients() {
    final keys = _keys;
    if (keys == null) return const <String, String>{};
    switch (target) {
      case DirectTarget(:final accountId):
        final other = _otherKey;
        if (other == null) return const <String, String>{};
        return <String, String>{
          _me: keys.public.encoded,
          accountId: other,
        };
    }
  }

  Map<String, Object?> _messageWrite(
    String id,
    MessageKind kind,
    Map<String, Object?> envelope,
  ) {
    final node = <String, Object?>{
      'at': serverTimestamp,
      'from': _me,
      'kind': kind.name,
      ...envelope,
    };
    switch (target) {
      case DirectTarget(:final accountId):
        final pair = directPairId(_me, accountId);
        final ends = directPairEnds(_me, accountId);
        return <String, Object?>{
          // `a` y `b` solo la primera vez: las reglas no dejan reescribirlos, y
          // mandarlos de nuevo tumbaria la operacion entera.
          if (_tree == null || (_tree as Map).isEmpty) ...<String, Object?>{
            'dm/$pair/a': ends.a,
            'dm/$pair/b': ends.b,
          },
          'dm/$pair/msgs/$id': node,
          'users/$accountId/inbox/$_me': <String, Object?>{'at': serverTimestamp},
        };
    }
  }

  /// Que sobra: lo que pase de 300 y lo que tenga mas de 90 dias.
  ///
  /// Lo borra quien escribe, en la misma operacion que manda, y por eso las
  /// reglas dejan a cualquiera de los dos borrar mensajes del otro. No hay
  /// tarea de limpieza en ninguna parte: la base se poda sola al usarse.
  Map<String, Object?> _pruneWrites() {
    final stored = _stored();
    if (stored.isEmpty) return const <String, Object?>{};
    final limite = DateTime.now().subtract(messageLifetime);
    final sobran = <String>[];
    // Uno menos de tope: el que se esta mandando ocupa su sitio.
    final exceso = stored.length - (messagesPerConversation - 1);
    for (var i = 0; i < stored.length; i++) {
      if (i < exceso || stored[i].at.isBefore(limite)) sobran.add(stored[i].id);
    }
    final prefijo = switch (target) {
      DirectTarget(:final accountId) => 'dm/${directPairId(_me, accountId)}',
    };
    return <String, Object?>{for (final id in sobran) '$prefijo/msgs/$id': null};
  }
}
