// Ibasho — nombres de piezas, personalidades y humores, ya traducidos.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';

String personalityLabel(L l, TamaPersonality p) => switch (p) {
      TamaPersonality.calm => l.tamaPersonalityCalm,
      TamaPersonality.playful => l.tamaPersonalityPlayful,
      TamaPersonality.shy => l.tamaPersonalityShy,
      TamaPersonality.cheeky => l.tamaPersonalityCheeky,
      TamaPersonality.sleepy => l.tamaPersonalitySleepy,
    };

String personalityHint(L l, TamaPersonality p) => switch (p) {
      TamaPersonality.calm => l.tamaPersonalityCalmHint,
      TamaPersonality.playful => l.tamaPersonalityPlayfulHint,
      TamaPersonality.shy => l.tamaPersonalityShyHint,
      TamaPersonality.cheeky => l.tamaPersonalityCheekyHint,
      TamaPersonality.sleepy => l.tamaPersonalitySleepyHint,
    };

String timbreLabel(L l, TamaTimbre t) => switch (t) {
      TamaTimbre.soft => l.tamaTimbreSoft,
      TamaTimbre.bright => l.tamaTimbreBright,
      TamaTimbre.round => l.tamaTimbreRound,
      TamaTimbre.whistle => l.tamaTimbreWhistle,
      TamaTimbre.purr => l.tamaTimbrePurr,
      TamaTimbre.bubble => l.tamaTimbreBubble,
    };

String foodLabel(L l, TamaFood food) => switch (food) {
      TamaFood.cookie => l.tamaFoodCookie,
      TamaFood.candy => l.tamaFoodCandy,
      TamaFood.cupcake => l.tamaFoodCupcake,
      TamaFood.apple => l.tamaFoodApple,
      TamaFood.dango => l.tamaFoodDango,
      TamaFood.mochi => l.tamaFoodMochi,
      TamaFood.lollipop => l.tamaFoodLollipop,
      TamaFood.iceCream => l.tamaFoodIceCream,
      TamaFood.donut => l.tamaFoodDonut,
      TamaFood.flan => l.tamaFoodFlan,
    };

/// Nombre de la variante `v` de una pieza.
String variantLabel(L l, TamaPart part, int v) {
  final names = switch (part) {
    TamaPart.body => [
        l.tamaBodyRound,
        l.tamaBodyBean,
        l.tamaBodyEgg,
        l.tamaBodyPear,
        l.tamaBodyMochi,
        l.tamaBodyDrop,
      ],
    TamaPart.eyes => [
        l.tamaEyesDot,
        l.tamaEyesShiny,
        l.tamaEyesSmile,
        l.tamaEyesSleepy,
        l.tamaEyesStar,
        l.tamaEyesGoggle,
      ],
    TamaPart.mouth => [
        l.tamaMouthSmile,
        l.tamaMouthCat,
        l.tamaMouthO,
        l.tamaMouthFang,
        l.tamaMouthTongue,
      ],
    TamaPart.crown => [
        l.tamaCrownNone,
        l.tamaCrownEars,
        l.tamaCrownBunny,
        l.tamaCrownAntennae,
        l.tamaCrownHorns,
        l.tamaCrownCurl,
      ],
    TamaPart.cheeks => [
        l.tamaCheeksNone,
        l.tamaCheeksBlush,
        l.tamaCheeksFreckles,
        l.tamaCheeksLines,
      ],
    TamaPart.pattern => [
        l.tamaPatternNone,
        l.tamaPatternBelly,
        l.tamaPatternSpots,
        l.tamaPatternStripes,
        l.tamaPatternTip,
      ],
    TamaPart.arms => [l.tamaArmsNubs, l.tamaArmsWings, l.tamaArmsMittens, l.tamaArmsNone],
    TamaPart.feet => [l.tamaFeetBeans, l.tamaFeetPaws, l.tamaFeetLegs, l.tamaFeetNone],
  };
  return names[v.clamp(0, names.length - 1)];
}

String moodLabel(L l, TamaMood mood) => switch (mood) {
      TamaMood.joyful => l.tamaMoodJoyful,
      TamaMood.content => l.tamaMoodContent,
      TamaMood.wistful => l.tamaMoodWistful,
      TamaMood.lonely => l.tamaMoodLonely,
    };

String moodHint(L l, TamaMood mood) => switch (mood) {
      TamaMood.joyful => l.tamaMoodHintJoyful,
      TamaMood.content => l.tamaMoodHintContent,
      TamaMood.wistful => l.tamaMoodHintWistful,
      TamaMood.lonely => l.tamaMoodHintLonely,
    };

/// "hace 3 horas", o "todavia nada" si nunca ha pasado.
String agoLabel(L l, DateTime? at, DateTime now) {
  if (at == null) return l.tamaNever;
  final since = now.difference(at);
  if (since.inMinutes < 60) return l.tamaAgoMinutes(since.inMinutes.clamp(0, 59));
  if (since.inHours < 24) return l.tamaAgoHours(since.inHours);
  return l.tamaAgoDays(since.inDays);
}
