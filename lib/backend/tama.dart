// Ibasho — modelo de datos de los Tamas.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../theme/tokens.dart';
import 'prizes.dart';

/// Version del esquema de `/tamas/{tamaId}`. Las reglas solo aceptan esta.
const int tamaSchema = 1;

/// Cuantos Tamas puede crear una cuenta. Las reglas lo aplican con el contador
/// `/users/{accountId}/tamaCount`; la app solo lo usa para avisar antes.
const int maxTamasPerAccount = 99;

/// Longitud permitida del nombre de un Tama.
const int tamaNameMax = 16;

/// Las cinco personalidades. El orden es el del selector del creador.
enum TamaPersonality {
  calm,
  playful,
  shy,
  cheeky,
  sleepy;

  static TamaPersonality byName(Object? raw) => values.firstWhere(
        (p) => p.name == raw,
        orElse: () => TamaPersonality.calm,
      );
}

/// Como se eligio el color del Tama. Se guarda para reabrir el creador en el
/// mismo modo.
enum TamaColorMode {
  /// Uno de los 16 tonos de la casa.
  palette,

  /// Cualquier `#RRGGBB`, sin limites.
  hex;

  static TamaColorMode byName(Object? raw) => values.firstWhere(
        (m) => m.name == raw,
        orElse: () => TamaColorMode.palette,
      );
}

/// Lo que se le puede dar de comer a un Tama.
///
/// No se guarda en el Tama: los cuidados solo apuntan cuando comio, no el que.
/// Las que no vienen de serie se venden bloqueadas en el Yatai: hoy solo se
/// pueden mirar, se desbloquearan cuando llegue su turno.
enum TamaFood {
  cookie(unlockedByDefault: true),
  candy(unlockedByDefault: true),
  cupcake,
  apple,
  dango,
  mochi,
  lollipop,
  iceCream,
  donut,
  flan;

  const TamaFood({this.unlockedByDefault = false});

  final bool unlockedByDefault;
}

/// Timbre de la voz.
enum TamaTimbre {
  soft,
  bright,
  round,
  whistle,
  purr,
  bubble;

  static TamaTimbre byIndex(int i) => values[i.clamp(0, values.length - 1)];
}

/// Una pieza del aspecto con varias variantes y su numero de variantes.
///
/// El numero es el tope que validan las reglas: si se anade una variante hay
/// que tocar tambien `database.rules.json`.
enum TamaPart {
  body(6),
  eyes(6),
  mouth(5),
  crown(6),
  cheeks(4),
  pattern(5),
  arms(4),
  feet(4);

  const TamaPart(this.variants);

  final int variants;
}

/// Lo que el Tama lleva puesto por encima de su aspecto.
///
/// Es una pieza mas del dibujo, pintada con el cuerpo, la cara y las orejas y
/// moviendose con ellos, pero no se guarda en `/tamas`: la pone el contexto.
/// Hoy solo hay una: el gorrito del dia del cumpleaños de su cuidador.
enum TamaWear {
  none,
  partyHat,
}

/// Los premios del gacha que lleva puestos: un gorro y hasta
/// [maxAccessories] accesorios, uno por [PrizeSlot].
///
/// Se guardan como claves de [PrizeItem] (`cap_red`): el gorro en
/// `look/hat` y los accesorios en `look/acc/a`, `b` y `c`, para que las
/// reglas comprueben cada uno contra la coleccion. Una clave que esta
/// version no conoce se conserva al guardar y no se pinta.
@immutable
class TamaOutfit {
  const TamaOutfit({this.hat, this.accessories = const <String>[]});

  static const TamaOutfit none = TamaOutfit();
  static const int maxAccessories = 3;

  /// Lo que aceptan las reglas en `look/hat` y en cada hueco de `look/acc`.
  static final RegExp keyPattern = RegExp(r'^[a-z0-9_]{1,40}$');

  final String? hat;
  final List<String> accessories;

  bool get isEmpty => hat == null && accessories.isEmpty;

  bool wears(String key) => hat == key || accessories.contains(key);

  /// Pone o quita [item]. Un gorro sustituye al gorro; un accesorio sustituye
  /// al que ocupe su sitio. Devuelve `null` si ya lleva [maxAccessories] y el
  /// nuevo no desplaza a ninguno.
  TamaOutfit? toggle(PrizeItem item) {
    if (item.prize.slot == PrizeSlot.head) {
      return TamaOutfit(hat: hat == item.key ? null : item.key, accessories: accessories);
    }
    if (accessories.contains(item.key)) {
      return TamaOutfit(hat: hat, accessories: [...accessories.where((k) => k != item.key)]);
    }
    final kept = [
      for (final k in accessories)
        if (prizeItem(k)?.prize.slot != item.prize.slot) k,
    ];
    if (kept.length >= maxAccessories) return null;
    return TamaOutfit(hat: hat, accessories: [...kept, item.key]);
  }

  /// Los huecos de `look/acc`, en orden.
  static const List<String> _slots = <String>['a', 'b', 'c'];

  /// `look/acc`, o `null` si no lleva accesorios.
  Map<String, String>? get accJson => accessories.isEmpty
      ? null
      : <String, String>{
          for (var i = 0; i < accessories.length && i < _slots.length; i++) _slots[i]: accessories[i],
        };

  static TamaOutfit fromJson(Object? hat, Object? acc) {
    final keys = switch (acc) {
      Map() => [
          for (final slot in _slots)
            if (acc[slot] is String) acc[slot] as String,
        ],
      // Antes de la coleccion se guardaban separados por comas.
      String() => acc.split(','),
      _ => const <String>[],
    };
    return TamaOutfit(
      hat: hat is String && keyPattern.hasMatch(hat) ? hat : null,
      accessories: [
        for (final k in keys.take(maxAccessories))
          if (keyPattern.hasMatch(k)) k,
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TamaOutfit && other.hat == hat && listEquals(other.accessories, accessories);

  @override
  int get hashCode => Object.hash(hat, Object.hashAll(accessories));
}

/// Los deslizadores del creador. Todos son enteros de 0 a 100.
enum TamaDial {
  bodyWidth,
  bodyHeight,
  eyeSize,
  eyeSpacing,
  eyeHeight,
  mouthSize,
  mouthHeight,
  crownSize,
  cheekIntensity,
  patternTone,
}

/// `#RRGGBB` a color. `null` si no es valido.
Color? colorFromHex(String hex) {
  final clean = hex.startsWith('#') ? hex.substring(1) : hex;
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

/// Color a `#RRGGBB` en mayusculas.
String hexFromColor(Color color) {
  final rgb = (color.r * 255).round() << 16 |
      (color.g * 255).round() << 8 |
      (color.b * 255).round();
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

final RegExp _hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');

/// Aspecto de un Tama: variantes, deslizadores y color.
///
/// Todo son enteros o cadenas de listas cerradas, que es lo que las reglas
/// pueden validar sin ambiguedad.
@immutable
class TamaLook {
  const TamaLook({
    this.parts = const <TamaPart, int>{},
    this.dials = const <TamaDial, int>{},
    this.color = '#5BC8F5',
    this.colorMode = TamaColorMode.palette,
    this.outfit = TamaOutfit.none,
  });

  final Map<TamaPart, int> parts;
  final Map<TamaDial, int> dials;

  /// `#RRGGBB`. Es el color final, venga de la paleta o del modo libre.
  final String color;

  final TamaColorMode colorMode;

  /// Lo que lleva puesto. Viaja con el aspecto: lo ven los amigos y se va con
  /// el Tama si se transfiere.
  final TamaOutfit outfit;

  static const Map<TamaDial, int> defaultDials = <TamaDial, int>{
    TamaDial.bodyWidth: 50,
    TamaDial.bodyHeight: 50,
    TamaDial.eyeSize: 50,
    TamaDial.eyeSpacing: 50,
    TamaDial.eyeHeight: 50,
    TamaDial.mouthSize: 50,
    TamaDial.mouthHeight: 50,
    TamaDial.crownSize: 50,
    TamaDial.cheekIntensity: 60,
    TamaDial.patternTone: 25,
  };

  /// Variante elegida de una pieza, siempre dentro de rango.
  int part(TamaPart p) => (parts[p] ?? 0).clamp(0, p.variants - 1);

  /// Valor de un deslizador, siempre entre 0 y 100.
  int dial(TamaDial d) => (dials[d] ?? defaultDials[d]!).clamp(0, 100);

  /// Deslizador como fraccion de 0 a 1.
  double unit(TamaDial d) => dial(d) / 100;

  Color get bodyColor => colorFromHex(color) ?? T.tamaPalette.first;

  TamaLook withPart(TamaPart p, int value) => TamaLook(
        parts: {...parts, p: value.clamp(0, p.variants - 1)},
        dials: dials,
        color: color,
        colorMode: colorMode,
        outfit: outfit,
      );

  TamaLook withDial(TamaDial d, int value) => TamaLook(
        parts: parts,
        dials: {...dials, d: value.clamp(0, 100)},
        color: color,
        colorMode: colorMode,
        outfit: outfit,
      );

  TamaLook withColor(String hex, TamaColorMode mode) => TamaLook(
        parts: parts,
        dials: dials,
        color: _hexPattern.hasMatch(hex) ? hex.toUpperCase() : color,
        colorMode: mode,
        outfit: outfit,
      );

  TamaLook withOutfit(TamaOutfit value) => TamaLook(
        parts: parts,
        dials: dials,
        color: color,
        colorMode: colorMode,
        outfit: value,
      );

  /// Un aspecto al azar, siempre con un color de la paleta: barajar tiene que
  /// dar un Tama bonito, no un experimento.
  static TamaLook random(math.Random rng) {
    int pick(TamaPart p) => rng.nextInt(p.variants);
    // Los deslizadores se quedan cerca del centro: en los extremos las
    // proporciones son para quien las busca a proposito.
    int near(int centre, int spread) =>
        (centre + rng.nextInt(spread * 2 + 1) - spread).clamp(0, 100);
    final palette = T.tamaPalette;
    return TamaLook(
      parts: {for (final p in TamaPart.values) p: pick(p)},
      dials: {
        TamaDial.bodyWidth: near(50, 22),
        TamaDial.bodyHeight: near(50, 22),
        TamaDial.eyeSize: near(52, 26),
        TamaDial.eyeSpacing: near(50, 22),
        TamaDial.eyeHeight: near(50, 20),
        TamaDial.mouthSize: near(50, 24),
        TamaDial.mouthHeight: near(50, 20),
        TamaDial.crownSize: near(55, 30),
        TamaDial.cheekIntensity: near(60, 30),
        TamaDial.patternTone: rng.nextInt(101),
      },
      color: hexFromColor(palette[rng.nextInt(palette.length)]),
      colorMode: TamaColorMode.palette,
    );
  }

  static TamaLook fromJson(Object? raw) {
    if (raw is! Map) return const TamaLook();
    int? intOf(String key) => (raw[key] as num?)?.toInt();
    return TamaLook(
      parts: {
        for (final p in TamaPart.values)
          if (intOf(p.name) != null) p: intOf(p.name)!,
      },
      dials: {
        for (final d in TamaDial.values)
          if (intOf(d.name) != null) d: intOf(d.name)!,
      },
      color: raw['color'] is String && _hexPattern.hasMatch(raw['color'] as String)
          ? (raw['color'] as String).toUpperCase()
          : '#5BC8F5',
      colorMode: TamaColorMode.byName(raw['colorMode']),
      outfit: TamaOutfit.fromJson(raw['hat'], raw['acc']),
    );
  }

  Map<String, Object?> toJson() => {
        for (final p in TamaPart.values) p.name: part(p),
        for (final d in TamaDial.values) d.name: dial(d),
        'color': color,
        'colorMode': colorMode.name,
        // Solo si lleva algo: un Tama sin premios se guarda como siempre.
        if (outfit.hat != null) 'hat': outfit.hat,
        'acc': ?outfit.accJson,
      };

  @override
  bool operator ==(Object other) =>
      other is TamaLook &&
      other.color == color &&
      other.colorMode == colorMode &&
      other.outfit == outfit &&
      TamaPart.values.every((p) => other.part(p) == part(p)) &&
      TamaDial.values.every((d) => other.dial(d) == dial(d));

  @override
  int get hashCode => Object.hash(
        color,
        colorMode,
        outfit,
        Object.hashAll(TamaPart.values.map(part)),
        Object.hashAll(TamaDial.values.map(dial)),
      );
}

/// Voz de un Tama. El patron de silabas sale del nombre; esto solo la colorea.
@immutable
class TamaVoice {
  const TamaVoice({this.pitch = 50, this.tempo = 50, this.timbre = TamaTimbre.soft});

  /// Tono, de grave (0) a agudo (100).
  final int pitch;

  /// Velocidad, de pausada (0) a atropellada (100).
  final int tempo;

  final TamaTimbre timbre;

  TamaVoice copyWith({int? pitch, int? tempo, TamaTimbre? timbre}) => TamaVoice(
        pitch: (pitch ?? this.pitch).clamp(0, 100),
        tempo: (tempo ?? this.tempo).clamp(0, 100),
        timbre: timbre ?? this.timbre,
      );

  static TamaVoice fromJson(Object? raw) {
    if (raw is! Map) return const TamaVoice();
    return TamaVoice(
      pitch: ((raw['pitch'] as num?)?.toInt() ?? 50).clamp(0, 100),
      tempo: ((raw['tempo'] as num?)?.toInt() ?? 50).clamp(0, 100),
      timbre: TamaTimbre.byIndex((raw['timbre'] as num?)?.toInt() ?? 0),
    );
  }

  Map<String, Object?> toJson() => {
        'pitch': pitch,
        'tempo': tempo,
        'timbre': timbre.index,
      };

  @override
  bool operator ==(Object other) =>
      other is TamaVoice &&
      other.pitch == pitch &&
      other.tempo == tempo &&
      other.timbre == timbre;

  @override
  int get hashCode => Object.hash(pitch, tempo, timbre);
}

/// Marcas de tiempo de los cuidados. El humor se calcula a partir de aqui, en
/// el cliente, y nunca se escribe.
@immutable
class TamaCare {
  const TamaCare({this.lastPetted, this.lastFed});

  final DateTime? lastPetted;
  final DateTime? lastFed;

  static TamaCare fromJson(Object? raw) {
    if (raw is! Map) return const TamaCare();
    DateTime? at(String key) {
      final v = raw[key];
      return v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    }

    return TamaCare(lastPetted: at('lastPetted'), lastFed: at('lastFed'));
  }

  Map<String, Object?> toJson() => {
        'lastPetted': ?lastPetted?.millisecondsSinceEpoch,
        'lastFed': ?lastFed?.millisecondsSinceEpoch,
      };

  TamaCare copyWith({DateTime? lastPetted, DateTime? lastFed}) => TamaCare(
        lastPetted: lastPetted ?? this.lastPetted,
        lastFed: lastFed ?? this.lastFed,
      );
}

/// Un Tama entero, tal como vive en `/tamas/{tamaId}`.
@immutable
class Tama {
  const Tama({
    required this.id,
    required this.creator,
    required this.keeper,
    required this.name,
    this.personality = TamaPersonality.calm,
    this.voice = const TamaVoice(),
    this.look = const TamaLook(),
    this.care = const TamaCare(),
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Cuenta que lo creo. Es la unica que edita nombre, aspecto, personalidad y
  /// voz, tambien despues de un traspaso.
  final String creator;

  /// Cuenta que lo cuida. Hoy siempre coincide con `creator`; traspasar un
  /// Tama sera cambiar este campo.
  final String keeper;

  final String name;
  final TamaPersonality personality;
  final TamaVoice voice;
  final TamaLook look;
  final TamaCare care;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool createdBy(String accountId) => creator == accountId;

  static Tama fromJson(String id, Map<Object?, Object?> json) {
    DateTime at(String key) => DateTime.fromMillisecondsSinceEpoch(
          (json[key] as num?)?.toInt() ?? 0,
        );
    return Tama(
      id: id,
      creator: (json['creator'] as String?) ?? '',
      keeper: (json['keeper'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      personality: TamaPersonality.byName(json['personality']),
      voice: TamaVoice.fromJson(json['voice']),
      look: TamaLook.fromJson(json['look']),
      care: TamaCare.fromJson(json['care']),
      createdAt: at('createdAt'),
      updatedAt: at('updatedAt'),
    );
  }

  /// El registro entero, con las marcas de tiempo en milisegundos.
  Map<String, Object?> toJson() => {
        'schema': tamaSchema,
        'creator': creator,
        'keeper': keeper,
        ...identityJson(),
        'care': care.toJson(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  /// Lo que edita el creador. Es exactamente lo que las reglas le dejan tocar.
  Map<String, Object?> identityJson() => {
        'name': name,
        'personality': personality.name,
        'voice': voice.toJson(),
        'look': look.toJson(),
      };

  Tama copyWith({
    String? name,
    TamaPersonality? personality,
    TamaVoice? voice,
    TamaLook? look,
    TamaCare? care,
    DateTime? updatedAt,
  }) =>
      Tama(
        id: id,
        creator: creator,
        keeper: keeper,
        name: name ?? this.name,
        personality: personality ?? this.personality,
        voice: voice ?? this.voice,
        look: look ?? this.look,
        care: care ?? this.care,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Humor de un Tama en un instante.
enum TamaMood {
  /// Recien mimado y comido.
  joyful,

  /// Bien, sin mas.
  content,

  /// Hace rato que nadie le hace caso.
  wistful,

  /// Un par de dias solo. Se pone melancolico; nunca enferma ni muere.
  lonely,
}

/// El humor, calculado siempre en el cliente a partir de las marcas de
/// cuidado. No hay ni una escritura periodica: si nadie lo toca, el humor
/// cambia solo porque cambia `now`.
@immutable
class TamaMoodReading {
  const TamaMoodReading(this.value);

  /// De 0 (melancolico) a 1 (radiante).
  final double value;

  /// Horas hasta que un cuidado deja de contar del todo.
  static const double fadeHours = 52;

  static TamaMoodReading of(Tama tama, DateTime now) {
    // Un Tama recien nacido esta contento: cuenta como cuidado reciente.
    double freshness(DateTime? at) {
      final since = at ?? tama.createdAt;
      final hours = now.difference(since).inMinutes / 60;
      if (hours <= 0) return 1;
      // Cae despacio al principio y mas deprisa despues: un rato sin atencion
      // no se nota, un dia entero si.
      final t = (hours / fadeHours).clamp(0.0, 1.0);
      return 1 - t * t * (3 - 2 * t);
    }

    final pet = freshness(tama.care.lastPetted);
    final fed = freshness(tama.care.lastFed);
    return TamaMoodReading((pet * .55 + fed * .45).clamp(0.0, 1.0));
  }

  TamaMood get mood {
    if (value >= .72) return TamaMood.joyful;
    if (value >= .42) return TamaMood.content;
    if (value >= .16) return TamaMood.wistful;
    return TamaMood.lonely;
  }

  /// De -1 (triste) a 1 (feliz), para la cara y las animaciones.
  double get joy => (value * 2 - 1).clamp(-1.0, 1.0);
}
