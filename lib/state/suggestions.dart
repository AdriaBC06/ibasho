// Ibasho — el buzon de sugerencias y su revision.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ibasho_backend.dart';
import '../backend/live_tree.dart';
import '../backend/models.dart';
import '../backend/push_id.dart';
import '../backend/suggestions.dart';
import 'session.dart';

@immutable
class SuggestionsState {
  const SuggestionsState({
    this.mine,
    this.accepted = const <AcceptedSuggestion>[],
    this.pending = const <Suggestion>[],
    this.open = true,
    this.loaded = false,
  });

  /// La ultima sugerencia de esta cuenta, con su veredicto si ya lo tiene.
  final Suggestion? mine;

  /// Las aceptadas, a la vista de todos.
  final List<AcceptedSuggestion> accepted;

  /// Todas las que esperan respuesta. Solo se llena si quien mira es admin.
  final List<Suggestion> pending;

  /// Si el buzon admite sugerencias nuevas.
  final bool open;

  final bool loaded;

  /// Se puede mandar otra cuando no hay ninguna esperando respuesta.
  bool get canSubmit => open && (mine == null || !mine!.isPending);

  SuggestionsState copyWith({
    Suggestion? mine,
    bool clearMine = false,
    List<AcceptedSuggestion>? accepted,
    List<Suggestion>? pending,
    bool? open,
    bool? loaded,
  }) =>
      SuggestionsState(
        mine: clearMine ? null : (mine ?? this.mine),
        accepted: accepted ?? this.accepted,
        pending: pending ?? this.pending,
        open: open ?? this.open,
        loaded: loaded ?? this.loaded,
      );
}

/// El buzon. Una sugerencia viva por cuenta: hasta que no hay veredicto no se
/// puede mandar otra, y eso lo aplican las reglas, no solo la pantalla.
class SuggestionsController extends StateNotifier<SuggestionsState> {
  SuggestionsController({
    required IbashoBackend backend,
    required SessionController session,
    required bool isAdmin,
  })  : _backend = backend,
        _session = session,
        _isAdmin = isAdmin,
        super(const SuggestionsState()) {
    if (_me.isNotEmpty && session.state.phase == SessionPhase.active) {
      unawaited(_start());
    }
  }

  final IbashoBackend _backend;
  final SessionController _session;
  final bool _isAdmin;

  final List<StreamSubscription<DatabaseEvent>> _watches = [];
  Object? _acceptedTree;
  Object? _allTree;

  String get _me => _session.state.accountId;

  @override
  void dispose() {
    for (final w in _watches) {
      unawaited(w.cancel());
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final token = await _session.freshToken();
      final results = await Future.wait([
        _backend.read('/suggestions/$_me', idToken: token),
        _backend.read('/acceptedSuggestions', idToken: token),
        _backend.read('/system/suggestionsOpen', idToken: token),
      ]);
      if (!mounted) return;
      _acceptedTree = results[1];
      state = SuggestionsState(
        mine: Suggestion.fromJson(_me, results[0]),
        accepted: _parseAccepted(_acceptedTree),
        open: results[2] != false,
        loaded: true,
      );
    } catch (e) {
      debugPrint('Ibasho: no se ha podido leer el buzon ($e)');
      if (mounted) state = state.copyWith(loaded: true);
    }
    if (!mounted) return;
    _listen();
  }

  void _listen() {
    _watches.add(
      _backend.watch('/suggestions/$_me', token: _session.freshToken).listen((e) {
        if (!mounted || e.path != '/') return;
        state = e.data == null
            ? state.copyWith(clearMine: true)
            : state.copyWith(mine: Suggestion.fromJson(_me, e.data));
      }, onError: (Object e) => debugPrint('Ibasho: stream de mi sugerencia ($e)')),
    );

    _watches.add(
      _backend.watch('/acceptedSuggestions', token: _session.freshToken).listen((e) {
        _acceptedTree = applyDatabaseEvent(_acceptedTree, e);
        if (mounted) state = state.copyWith(accepted: _parseAccepted(_acceptedTree));
      }, onError: (Object e) => debugPrint('Ibasho: stream de aceptadas ($e)')),
    );

    _watches.add(
      _backend
          .watch('/system/suggestionsOpen', token: _session.freshToken)
          .listen((e) {
        if (mounted && e.path == '/') state = state.copyWith(open: e.data != false);
      }, onError: (Object e) => debugPrint('Ibasho: stream del buzon ($e)')),
    );

    if (_isAdmin) {
      _watches.add(
        _backend.watch('/suggestions', token: _session.freshToken).listen((e) {
          _allTree = applyDatabaseEvent(_allTree, e);
          if (mounted) state = state.copyWith(pending: _parsePending(_allTree));
        }, onError: (Object e) => debugPrint('Ibasho: stream de sugerencias ($e)')),
      );
    }
  }

  /// Manda una sugerencia. Sustituye a la anterior, que ya tendra veredicto.
  Future<bool> submit({required String title, required String body}) async {
    if (!state.canSubmit) return false;
    try {
      final token = await _session.freshToken();
      await _backend.write(
        '/suggestions/$_me',
        <String, Object?>{
          'title': title,
          'body': body,
          'at': serverTimestamp,
          'status': SuggestionStatus.pending.name,
        },
        idToken: token,
      );
      return true;
    } catch (e) {
      debugPrint('Ibasho: la sugerencia no ha salido ($e)');
      return false;
    }
  }

  // --- Solo admin --------------------------------------------------------

  /// Acepta o rechaza. Al aceptar, la sugerencia pasa ademas a la lista
  /// publica, con el nombre de quien la propuso.
  Future<bool> decide({
    required Suggestion suggestion,
    required bool accept,
    String note = '',
    required String decidedBy,
    required String authorName,
  }) async {
    final status =
        accept ? SuggestionStatus.accepted.name : SuggestionStatus.rejected.name;
    final writes = <String, Object?>{
      'suggestions/${suggestion.accountId}/status': status,
      'suggestions/${suggestion.accountId}/decidedAt': serverTimestamp,
      'suggestions/${suggestion.accountId}/decidedBy': decidedBy,
      'suggestions/${suggestion.accountId}/note': note.isEmpty ? null : note,
      if (accept)
        'acceptedSuggestions/${generatePushId()}': <String, Object?>{
          'title': suggestion.title,
          'by': authorName,
          'at': serverTimestamp,
        },
    };
    try {
      final token = await _session.freshToken();
      await _backend.merge('/', writes, idToken: token);
      return true;
    } catch (e) {
      debugPrint('Ibasho: el veredicto no ha entrado ($e)');
      return false;
    }
  }

  /// Abre o cierra el buzon para todo el mundo.
  Future<bool> setOpen(bool open) async {
    try {
      final token = await _session.freshToken();
      await _backend.write('/system/suggestionsOpen', open, idToken: token);
      if (mounted) state = state.copyWith(open: open);
      return true;
    } catch (e) {
      debugPrint('Ibasho: no se ha podido cambiar el buzon ($e)');
      return false;
    }
  }

  static List<AcceptedSuggestion> _parseAccepted(Object? raw) {
    if (raw is! Map) return const <AcceptedSuggestion>[];
    final out = <AcceptedSuggestion>[];
    for (final e in raw.entries) {
      final item = AcceptedSuggestion.fromJson('${e.key}', e.value);
      if (item != null) out.add(item);
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return List<AcceptedSuggestion>.unmodifiable(out);
  }

  static List<Suggestion> _parsePending(Object? raw) {
    if (raw is! Map) return const <Suggestion>[];
    final out = <Suggestion>[];
    for (final e in raw.entries) {
      final item = Suggestion.fromJson('${e.key}', e.value);
      if (item != null && item.isPending) out.add(item);
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return List<Suggestion>.unmodifiable(out);
  }
}
