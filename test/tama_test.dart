// Ibasho — los Tamas: criterios de aceptacion del checkpoint 2.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibasho/app.dart';
import 'package:ibasho/audio/audio_service.dart';
import 'package:ibasho/audio/tama_voice.dart';
import 'package:ibasho/backend/live_tree.dart';
import 'package:ibasho/backend/models.dart';
import 'package:ibasho/backend/push_id.dart';
import 'package:ibasho/backend/tama.dart';
import 'package:ibasho/state/accent_sync.dart';
import 'package:ibasho/state/providers.dart';
import 'package:ibasho/storage/settings_store.dart';
import 'package:ibasho/theme/accent.dart';
import 'package:ibasho/theme/tokens.dart';
import 'package:ibasho/ui/tama/tama_animator.dart';
import 'package:ibasho/ui/tama/tama_painter.dart';
import 'package:ibasho/ui/tama/tama_view.dart';
import 'package:ibasho/ui/widgets/color_picker.dart';
import 'package:ibasho/ui/widgets/controls.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fakes.dart';

Future<void> main() async {
  await initializeDateFormatting('es');
  await initializeDateFormatting('en');

  Future<void> settle(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<FakeIbashoBackend> boot(
    WidgetTester tester, {
    FakeIbashoBackend? backend,
    Preferences preferences = const Preferences(),
  }) async {
    tester.view.physicalSize = T.canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = backend ?? FakeIbashoBackend();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(fake),
          secureStoreProvider.overrideWithValue(FakeSecureStore(session: fake.tokens)),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()..saved = preferences),
          initialPreferencesProvider.overrideWithValue(preferences),
        ],
        child: const IbashoApp(),
      ),
    );
    await settle(tester, 100);
    return fake;
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(IbashoApp)));

  Future<void> tapKey(WidgetTester tester, String key, [int frames = 30]) async {
    final finder = find.byKey(ValueKey<String>(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle(tester, frames);
  }

  Future<void> closeTop(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, 30);
  }

  Iterable<TamaView> viewsIn(String key) => find
      .descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(TamaView))
      .evaluate()
      .map((e) => e.widget as TamaView);

  // --- 1. Crear ----------------------------------------------------------------

  testWidgets('un Tama nuevo se guarda y aparece al instante arriba y en el perfil',
      (tester) async {
    final backend = await boot(tester);
    expect(viewsIn('top.tama'), isEmpty, reason: 'sin Tama, solo la silueta');

    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.createEmpty', 40);
    await tapKey(tester, 'creator.tab.character', 12);
    await tester.enterText(
      find.descendant(
          of: find.byKey(const ValueKey<String>('creator.name')),
          matching: find.byType(EditableText)),
      'Tommy',
    );
    await settle(tester, 4);
    await tapKey(tester, 'creator.save', 40);

    // Guardado en la base, con contador y como Tama de perfil.
    final stored = backend.peek('/tamas') as Map;
    expect(stored, hasLength(1));
    final id = stored.keys.single as String;
    expect(RegExp(r'^[-0-9A-Za-z_]{20}$').hasMatch(id), isTrue);
    expect((stored[id] as Map)['name'], 'Tommy');
    expect(backend.peek('/users/$kAdminUid/tamaCount'), 1);
    expect(backend.peek('/users/$kAdminUid/tamaLastChange'), id);
    expect(backend.peek('/users/$kAdminUid/tama'), id);

    // Al crear se pasa a su habitacion. Detras, en el panel superior, ya esta.
    expect(find.byKey(const ValueKey<String>('tama.stage')), findsOneWidget);
    await closeTop(tester);
    await closeTop(tester);
    expect(viewsIn('top.tama').single.name, 'Tommy');

    await tapKey(tester, 'channel.profile', 60);
    expect(viewsIn('profile.tama').single.name, 'Tommy');
  });

  // --- 2. Editar en vivo -------------------------------------------------------

  testWidgets('editar el aspecto se refleja en vivo en todas las vistas abiertas',
      (tester) async {
    final tama = sampleTama();
    final backend = await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
    );
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);

    final everywhere = find.byType(TamaView, skipOffstage: false);
    expect(everywhere.evaluate().length, greaterThanOrEqualTo(2),
        reason: 'habitacion abierta y el panel superior debajo');

    // Otro equipo del creador cambia el color y la forma.
    backend.seed('/tamas/${tama.id}/look/color', '#123456');
    backend.seed('/tamas/${tama.id}/look/body', 4);
    await settle(tester, 4);
    for (final view in everywhere.evaluate().map((e) => e.widget as TamaView)) {
      expect(view.look.color, '#123456');
      expect(view.look.part(TamaPart.body), 4);
    }

    // Y desde el creador de esta misma sesion.
    await tapKey(tester, 'tama.edit', 40);
    await tapKey(tester, 'creator.body.2', 10);
    await tapKey(tester, 'creator.save', 40);
    expect((backend.peek('/tamas/${tama.id}/look') as Map)['body'], 2);
    for (final view in find.byType(TamaView, skipOffstage: false).evaluate().map((e) => e.widget as TamaView)) {
      expect(view.look.part(TamaPart.body), 2);
    }
    await settle(tester, 80); // que se vaya el aviso de guardado
  });

  // --- 3. Paleta y HEX ---------------------------------------------------------

  testWidgets('la paleta y el HEX libre funcionan y el modo elegido se recuerda',
      (tester) async {
    final tama = sampleTama();
    final backend = await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
    );
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);

    // Paleta.
    await tapKey(tester, 'tama.edit', 40);
    await tapKey(tester, 'creator.tab.color', 12);
    await tapKey(tester, 'creator.palette.2', 8);
    await tapKey(tester, 'creator.save', 40);
    var look = backend.peek('/tamas/${tama.id}/look') as Map;
    expect(look['color'], hexFromColor(T.tamaPalette[2]));
    expect(look['colorMode'], 'palette');

    // HEX libre, con un color que la paleta no tiene y sin limites.
    await tapKey(tester, 'tama.edit', 40);
    await tapKey(tester, 'creator.tab.color', 12);
    await tester.tap(find.text('HEX libre'));
    await settle(tester, 10);
    await tester.enterText(
      find.descendant(
          of: find.byKey(const ValueKey<String>('creator.hex')),
          matching: find.byType(EditableText)),
      '#6B4F3A',
    );
    await settle(tester, 4);
    await tapKey(tester, 'creator.save', 40);
    look = backend.peek('/tamas/${tama.id}/look') as Map;
    expect(look['color'], '#6B4F3A');
    expect(look['colorMode'], 'hex');

    // Al volver a abrirlo, el creador esta en modo HEX.
    await tapKey(tester, 'tama.edit', 40);
    await tapKey(tester, 'creator.tab.color', 12);
    expect(find.byType(HsvColorPicker), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('creator.palette.0')), findsNothing);
  });

  // --- 6. Humor sin escrituras -------------------------------------------------

  testWidgets('el humor se calcula en cliente y nada escribe periodicamente',
      (tester) async {
    final tama = sampleTama();
    final backend = await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
    );
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);
    backend.writes.clear();

    // Veinte minutos con la habitacion abierta y el reloj corriendo.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(minutes: 1));
    }
    expect(
      backend.writes.where((w) => w.$1.contains('tama') || w.$1.contains('care')),
      isEmpty,
    );

    // Una chuche que aun no se tiene no da de comer: avisa de la tienda.
    await tapKey(tester, 'tama.feed.candy', 4);
    backend.writes.clear();
    await tester.tap(find.byKey(const ValueKey<String>('tama.feed.cupcake'), skipOffstage: false),
        warnIfMissed: false);
    await settle(tester, 6);
    expect(backend.writes, isEmpty);
    await settle(tester, 80);

    // Solo un cuidado de verdad escribe, y solo su marca de tiempo.
    await tapKey(tester, 'tama.pet', 10);
    expect(backend.writes.map((w) => w.$1), ['/tamas/${tama.id}/care/lastPetted']);
    expect(backend.writes.single.$2, serverTimestamp);
  });

  test('el humor baja despacio con el tiempo y nunca pasa de melancolico', () {
    final base = DateTime(2026, 9, 15, 12);
    final tama = Tama(
      id: 'x',
      creator: 'a',
      keeper: 'a',
      name: 'x',
      care: TamaCare(lastPetted: base, lastFed: base),
      createdAt: base.subtract(const Duration(days: 30)),
      updatedAt: base,
    );
    final moods = [
      for (final hours in [0, 6, 24, 40, 72, 24 * 30])
        TamaMoodReading.of(tama, base.add(Duration(hours: hours))),
    ];
    expect(moods.first.mood, TamaMood.joyful);
    expect(moods[1].mood, TamaMood.joyful, reason: 'un rato sin atencion no se nota');
    expect(moods.last.mood, TamaMood.lonely);
    for (var i = 1; i < moods.length; i++) {
      expect(moods[i].value, lessThanOrEqualTo(moods[i - 1].value));
    }
    expect(moods.last.value, 0);
    // Un Tama recien nacido esta contento aunque nunca lo hayan cuidado.
    final newborn = Tama(id: 'y', creator: 'a', keeper: 'a', name: 'y', createdAt: base, updatedAt: base);
    expect(TamaMoodReading.of(newborn, base).mood, TamaMood.joyful);
  });

  // --- 7. Movimiento reducido --------------------------------------------------

  List<double> poseOf(WidgetTester tester, String key) {
    final paint = find
        .descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is TamaPainter),
        )
        .evaluate()
        .single
        .widget as CustomPaint;
    final p = (paint.painter! as TamaPainter).pose;
    return [
      p.breathe, p.squash, p.hop, p.tilt, p.lean, p.blink, p.gaze.dx, p.gaze.dy,
      p.happyEyes, p.mouthOpen, p.tongue, p.blush, p.sway, p.armWave, p.doze, p.hearts,
    ];
  }

  testWidgets('con movimiento reducido el Tama mantiene una pose fija', (tester) async {
    final tama = sampleTama();
    await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
      preferences: const Preferences(reducedMotion: true),
    );
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);

    final before = poseOf(tester, 'tama.stage');
    // Tocarlo, mimarlo, darle de comer y dejar pasar el tiempo.
    await tester.tap(find.byKey(const ValueKey<String>('tama.stage')));
    await tapKey(tester, 'tama.pet', 10);
    await tapKey(tester, 'tama.feed.cookie', 10);
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(poseOf(tester, 'tama.stage'), before);
    }
  });

  testWidgets('sin movimiento reducido el mismo Tama si se mueve', (tester) async {
    final tama = sampleTama();
    await boot(tester, backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id));
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);
    final seen = <String>{};
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(poseOf(tester, 'tama.stage').join(','));
    }
    expect(seen.length, greaterThan(30));
  });

  // --- 8. Nada de Material -----------------------------------------------------

  test('ningun archivo de la app importa Material ni Cupertino', () {
    final offenders = <String>[
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            RegExp(r"package:flutter/(material|cupertino)\.dart").hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
    expect(File('pubspec.yaml').readAsStringSync(), contains('uses-material-design: false'));
  });

  testWidgets('el creador no tiene ni un control de Material', (tester) async {
    final tama = sampleTama();
    await boot(tester, backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id));
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);
    await tapKey(tester, 'tama.edit', 40);

    const material = {
      'Material', 'Slider', 'RangeSlider', 'InkWell', 'Ink', 'InkResponse', 'TextField',
      'ElevatedButton', 'TextButton', 'OutlinedButton', 'FilledButton', 'IconButton',
      'Switch', 'Checkbox', 'Radio', 'Scaffold', 'AppBar', 'Tab', 'TabBar', 'Chip',
      'SnackBar', 'Tooltip', 'Card', 'Divider', 'Icon',
    };
    for (final tab in ['body', 'color', 'eyes', 'mouth', 'crown', 'cheeks', 'limbs', 'character']) {
      await tapKey(tester, 'creator.tab.$tab', 10);
      final types = <String>{
        for (final element in find.byWidgetPredicate((_) => true).evaluate())
          element.widget.runtimeType.toString(),
      };
      expect(types.intersection(material), isEmpty, reason: 'pestaña $tab');
    }
    // Los deslizadores del creador son los propios.
    await tapKey(tester, 'creator.tab.eyes', 10);
    expect(find.byType(IbashoSlider), findsNWidgets(3));
  });

  // --- 9. Idioma ---------------------------------------------------------------

  testWidgets('cambiar el idioma traduce el creador entero', (tester) async {
    final tama = sampleTama();
    await boot(tester, backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id));
    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);
    await tapKey(tester, 'tama.edit', 40);

    Future<void> expectTexts(String tab, List<String> texts, List<String> absent) async {
      await tapKey(tester, 'creator.tab.$tab', 10);
      for (final t in texts) {
        expect(find.text(t), findsWidgets, reason: '"$t" en $tab');
      }
      for (final t in absent) {
        expect(find.text(t), findsNothing, reason: '"$t" no deberia estar en $tab');
      }
    }

    await expectTexts('crown', ['coronilla', 'de conejo', 'antenas', 'tamaño'], ['bunny']);
    await expectTexts('character', ['juguetón', 'dormilón', 'voz', 'timbre', 'escuchar'], ['playful']);

    await container(tester).read(preferencesProvider.notifier).setLocale('en');
    await settle(tester, 10);

    await expectTexts('body', ['body', 'round', 'bean', 'mochi', 'width'], ['cuerpo', 'alubia']);
    await expectTexts('crown', ['crown', 'bunny', 'antennae', 'size'], ['de conejo', 'coronilla']);
    await expectTexts('eyes', ['eyes', 'googly', 'drowsy', 'spacing'], ['saltones']);
    await expectTexts('mouth', ['mouth', 'fang', 'little o'], ['colmillo']);
    await expectTexts('cheeks', ['cheeks', 'freckles', 'intensity'], ['pecas']);
    await expectTexts('limbs', ['arms & feet', 'wings', 'paws'], ['alitas']);
    await expectTexts('color', ['palette', 'free HEX', 'pattern', 'spots'], ['paleta', 'motas']);
    await expectTexts('character', [
      'calm', 'playful', 'shy', 'cheeky', 'sleepy', 'voice', 'pitch', 'listen',
    ], ['juguetón', 'tímido', 'voz']);
    expect(find.text('edit Tommy'), findsOneWidget);
  });

  // --- 10. Voz -----------------------------------------------------------------

  test('dos Tamas con nombres distintos no graznan igual, y uno siempre igual', () {
    const voice = TamaVoice();
    final tommy = synthesizeChirp(name: 'Tommy', voice: voice, kind: ChirpKind.hello);
    final again = synthesizeChirp(name: 'Tommy', voice: voice, kind: ChirpKind.hello);
    final mochi = synthesizeChirp(name: 'Mochi', voice: voice, kind: ChirpKind.hello);
    expect(tommy, again);
    expect(tommy, isNot(mochi));

    // No solo cambian los bytes: cambia la melodia.
    String melody(String name) => chirpPattern(name, voice, ChirpKind.hello)
        .map((s) => '${s.semitones.round()}/${(s.seconds * 1000).round()}')
        .join(' ');
    final names = ['Tommy', 'Mochi', 'Bruma', 'Pip', 'Luna', 'Kiwi', 'Nube', 'Tofu'];
    expect(names.map(melody).toSet().length, names.length);

    // Suena limpio: sin saturar y sin clic al empezar ni al acabar, en todas
    // las frases, voces y timbres.
    for (final kind in ChirpKind.values) {
      for (final timbre in TamaTimbre.values) {
        for (final pitch in [0, 50, 100]) {
          final wav = synthesizeChirp(
            name: 'Tommy',
            voice: TamaVoice(pitch: pitch, tempo: 100 - pitch, timbre: timbre),
            kind: kind,
          );
          final data = ByteData.sublistView(wav, 44);
          final count = data.lengthInBytes ~/ 2;
          var peak = 0;
          for (var i = 0; i < count; i++) {
            peak = math.max(peak, data.getInt16(i * 2, Endian.little).abs());
          }
          expect(peak, lessThan(32767 * .9), reason: '$kind $timbre $pitch');
          expect(peak, greaterThan(32767 * .15), reason: 'que se oiga');
          expect(data.getInt16(0, Endian.little).abs(), lessThan(400));
          expect(data.getInt16((count - 1) * 2, Endian.little).abs(), lessThan(400));
        }
      }
    }

    // Es un WAV valido de verdad.
    expect(String.fromCharCodes(tommy.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(tommy.sublist(8, 12)), 'WAVE');
    expect(tommy.length, greaterThan(44 + 44100 * .15 * 2));
  });

  test('los graznidos obedecen al volumen de efectos', () async {
    // Van por SoLoud, igual que los efectos: su volumen global es el de
    // efectos. Con los efectos a cero ni siquiera se sintetiza nada.
    final audio = AudioService.instance;
    final before = audio.effectsVolume;
    await audio.setEffectsVolume(0);
    expect(await audio.chirp(name: 'Tommy', voice: const TamaVoice()), 0);
    await audio.setEffectsVolume(before);
  });

  // --- Acento ------------------------------------------------------------------

  test('un acento sale legible aunque el Tama sea clarisimo', () {
    for (final hex in ['#FFFFFF', '#FFFFE0', '#EEF2F6', '#F3D95A', '#A6DA62', '#000000', '#6B4F3A']) {
      final accent = accentForTama(hex);
      final contrast = contrastRatio(accent, T.shellTop);
      expect(contrast, greaterThanOrEqualTo(minAccentContrast), reason: hex);
      expect(contrast, lessThanOrEqualTo(maxAccentContrast + .01), reason: hex);
    }
    // Un color que ya se lee bien no se toca.
    expect(accentForTama('#5BC8F5'), T.cyan);
  });

  test('el acento sigue al Tama sin pisar nunca uno elegido a mano', () {
    UserProfile profile({String accent = '#5BC8F5', bool? follows}) => UserProfile(
          username: 'x',
          displayName: 'x',
          accentColor: accent,
          accentFollowsTama: follows,
          createdAt: DateTime(2026),
        );
    const pink = '#F47AA6';
    final pinkAccent = hexFromColor(accentForTama(pink));

    // Nunca elegido y con el cian de serie: se sincroniza solo.
    expect(decideAccentSync(profile(), pink), AccentSync.follow);
    // Sincronizado: se actualiza solo.
    expect(decideAccentSync(profile(accent: '#7E9BF2', follows: true), pink), AccentSync.follow);
    expect(decideAccentSync(profile(accent: pinkAccent, follows: true), pink), AccentSync.none);
    // Tocado a mano: se pregunta.
    expect(decideAccentSync(profile(accent: '#7E9BF2', follows: false), pink), AccentSync.ask);
    expect(decideAccentSync(profile(accent: '#7E9BF2'), pink), AccentSync.ask);

    final followed = followTama(profile(accent: '#7E9BF2', follows: false), pink);
    expect(followed.accentFollowsTama, isTrue);
    expect(followed.accentColor, pinkAccent);
  });

  testWidgets('con el acento sincronizado, el entorno cambia con el color del Tama',
      (tester) async {
    final tama = sampleTama();
    final backend = await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
    );
    final c = container(tester);
    expect(c.read(accentProvider), T.cyan);

    final profile = c.read(profileProvider).profile!;
    await c.read(profileProvider.notifier).save(followTama(profile, tama.look.color));
    await settle(tester, 4);
    expect(c.read(accentProvider), accentForTama(tama.look.color));

    backend.seed('/tamas/${tama.id}/look/color', '#FFFFE0');
    await settle(tester, 4);
    expect(c.read(accentProvider), accentForTama('#FFFFE0'));
    expect(contrastRatio(c.read(accentProvider), T.shellTop), greaterThanOrEqualTo(minAccentContrast));
  });

  testWidgets('cambiar el color con un acento elegido a mano pregunta antes', (tester) async {
    final tama = sampleTama();
    final backend = await boot(
      tester,
      backend: FakeIbashoBackend(tamas: [tama], profileTamaId: tama.id),
    );
    final c = container(tester);
    final profile = c.read(profileProvider).profile!;
    await c.read(profileProvider.notifier).save(
        profile.copyWith(accentColor: '#7E9BF2', accentFollowsTama: false));
    await settle(tester, 4);

    await tapKey(tester, 'channel.tamas', 60);
    await tapKey(tester, 'tamas.card.${tama.id}', 40);
    await tapKey(tester, 'tama.edit', 40);
    await tapKey(tester, 'creator.tab.color', 12);
    await tapKey(tester, 'creator.palette.3', 8);
    await tapKey(tester, 'creator.save', 30);

    // El aviso esta delante y el acento sigue siendo el elegido a mano.
    expect(find.text('tu Tama ha cambiado de color'), findsOneWidget);
    expect((backend.peek('/users/$kAdminUid/profile') as Map)['accentColor'], '#7E9BF2');

    await tester.tap(find.text('seguir a mi Tama'));
    await settle(tester, 30);
    final stored = backend.peek('/users/$kAdminUid/profile') as Map;
    expect(stored['accentFollowsTama'], isTrue);
    expect(stored['accentColor'], hexFromColor(accentForTama(hexFromColor(T.tamaPalette[3]))));
    await settle(tester, 80); // que se vaya el aviso de guardado
  });

  // --- Piezas sueltas ----------------------------------------------------------

  test('los ids nuevos tienen la forma que exigen las reglas y salen en orden', () {
    final ids = [for (var i = 0; i < 200; i++) generatePushId()];
    for (final id in ids) {
      expect(RegExp(r'^[-0-9A-Za-z_]{20}$').hasMatch(id), isTrue);
    }
    expect([...ids]..sort(), ids);
    expect(ids.toSet().length, ids.length);
  });

  test('el arbol en vivo aplica put y patch como la base', () {
    Object? tree;
    tree = applyDatabaseEvent(tree, const DatabaseEvent(
        path: '/', data: {'a': {'name': 'x', 'look': {'body': 1}}}, isPatch: false));
    tree = applyDatabaseEvent(tree, const DatabaseEvent(
        path: '/a/look', data: {'body': 3, 'eyes': 2}, isPatch: true));
    tree = applyDatabaseEvent(tree, const DatabaseEvent(
        path: '/b', data: {'name': 'y'}, isPatch: false));
    expect(tree, {
      'a': {'name': 'x', 'look': {'body': 3, 'eyes': 2}},
      'b': {'name': 'y'},
    });
    tree = applyDatabaseEvent(tree, const DatabaseEvent(path: '/a', data: null, isPatch: false));
    expect(tree, {'b': {'name': 'y'}});
  });

  test('un aspecto sobrevive a guardarse y leerse, y barajar da siempre algo valido', () {
    final rng = math.Random(3);
    for (var i = 0; i < 200; i++) {
      final look = TamaLook.random(rng);
      expect(TamaLook.fromJson(look.toJson()), look);
      for (final part in TamaPart.values) {
        expect(look.part(part), inInclusiveRange(0, part.variants - 1));
      }
      expect(T.tamaPalette.map(hexFromColor), contains(look.color));
    }
  });

  test('cada personalidad tiene su ritmo', () {
    Map<String, int> blinksPerMinute() => {
          for (final p in TamaPersonality.values)
            p.name: () {
              final animator = TamaAnimator(personality: p, seed: 1);
              var blinks = 0;
              var closed = false;
              for (var t = 0; t < 60 * 60; t++) {
                final pose = animator.tick(1 / 60);
                if (pose.blink > .9 && !closed) blinks++;
                closed = pose.blink > .9;
              }
              return blinks;
            }(),
        };
    final blinks = blinksPerMinute();
    expect(blinks['shy']!, greaterThan(blinks['sleepy']!));
    expect(blinks['playful']!, greaterThan(blinks['calm']!));

    // Un toque al jugueton le hace saltar; al timido, no.
    double highest(TamaPersonality p) {
      final animator = TamaAnimator(personality: p, seed: 2)..poke();
      var top = 0.0;
      for (var i = 0; i < 90; i++) {
        top = math.max(top, animator.tick(1 / 60).hop);
      }
      return top;
    }

    expect(highest(TamaPersonality.playful), greaterThan(5));
    expect(highest(TamaPersonality.shy), 0);
  });
}
