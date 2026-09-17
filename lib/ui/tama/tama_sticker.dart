// Ibasho — stickers: un Tama tuyo puesto con una cara concreta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

import '../../backend/messaging.dart';
import '../../backend/tama.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/type.dart';
import 'tama_painter.dart';

/// La postura de cada cara de sticker.
///
/// Un sticker no es un dibujo aparte: es el mismo [TamaPainter] de siempre con
/// una [TamaPose] fija. Por eso el catalogo entero cabe en ocho constantes y no
/// hay ni un mapa de bits que descargar, ni una pieza nueva que mantener.
///
/// Las ocho devueltas son `const` a proposito: [TamaPose] no tiene `==`, asi
/// que `TamaPainter.shouldRepaint` las compara por identidad. Con constantes
/// canonicas, reconstruir la hoja (elegir otra cara, mover el raton por la
/// rejilla) no repinta ni uno solo de los dieciseis Tamas que hay en pantalla:
/// solo repintan los que cambian de `look`.
TamaPose poseForFace(StickerFace face) => switch (face) {
      StickerFace.happy => _happy,
      StickerFace.wink => _wink,
      StickerFace.surprised => _surprised,
      StickerFace.angry => _angry,
      StickerFace.love => _love,
      StickerFace.sad => _sad,
      StickerFace.sleepy => _sleepy,
      StickerFace.wave => _wave,
    };

/// Contento: ojos cerrados de gusto, boca abierta de risa y un salto corto.
/// El salto es lo que lo separa de `love` de un vistazo cuando el Tama no
/// tiene corazones todavia en pantalla.
const TamaPose _happy = TamaPose(
  joy: 1,
  happyEyes: 1,
  mouthOpen: .48,
  hop: 5.5,
  squash: -.08,
  blush: .22,
  sway: .3,
  breathe: .6,
);

/// Guino.
///
/// El pintor no sabe cerrar un ojo solo: `_eye` recibe la misma pose para el
/// lado -1 y para el +1, y tanto `blink` como `happyEyes` se aplican a los dos
/// por igual (lo unico que mira el lado es la pestana del ojo somnoliento).
/// Un guino de verdad pediria un campo nuevo en [TamaPose] y una rama nueva en
/// el pintor, y el pintor no se toca: aqui el guino se resuelve como picardia,
/// que es lo que un guino quiere decir. Los ojos se quedan a media asta con un
/// `blink` largo —entornados, no cerrados—, la cabeza se ladea fuerte, asoma la
/// lengua y sube el rubor. A 96 pixeles se lee "listillo" y no se confunde con
/// `sleepy` (que trae parpados de piel y zetas) ni con `angry` (que entorna
/// igual pero con la boca hacia abajo y mirando para otro lado).
const TamaPose _wink = TamaPose(
  joy: .95,
  blink: .58,
  tongue: .6,
  tilt: .17,
  lean: 1.4,
  blush: .5,
  sway: .35,
  hop: 1.5,
);

/// Sorpresa: ojos abiertos del todo (`blink` a cero, sin parpado ni ceja), la
/// boca al maximo y el cuerpo estirado hacia arriba con un `squash` negativo
/// grande. El tamano del ojo sale del aspecto del Tama, no de la pose, asi que
/// lo que hace el trabajo es el contraste: es la unica cara con el cuerpo
/// alargado y el unico boston de boca de este tamano.
const TamaPose _surprised = TamaPose(
  joy: .15,
  blink: 0,
  mouthOpen: 1,
  squash: -.38,
  hop: 4,
  sway: .7,
  breathe: -1,
);

/// Enfado.
///
/// Con alegria negativa el pintor pone puchero y cejas de preocupacion (las
/// cejas caidas se leian como enfado y se decidio al reves, ver `_eye`), asi
/// que el enfado y la tristeza comparten media cara. Lo que los separa aqui:
/// ojos entornados, cabeza muy ladeada, mirada apartada a un lado, rubor bajo
/// de sofoco y los bracitos algo subidos. Sale un enfurrunado, que es justo lo
/// que dice la etiqueta ("enfado", "cross"), no una furia.
const TamaPose _angry = TamaPose(
  joy: -.72,
  blink: .34,
  tilt: .19,
  gaze: Offset(-.6, -.15),
  blush: .3,
  squash: .2,
  sway: -.55,
  armWave: .25,
);

/// Amor: los corazones lo dicen todo a cualquier tamano. La fase esta elegida
/// para que los tres esten a media subida y se vean los tres (con fase 0 el
/// primero sale transparente).
const TamaPose _love = TamaPose(
  joy: .9,
  happyEyes: 1,
  blush: .95,
  hearts: 1,
  heartPhase: .2,
  tilt: .1,
  sway: .2,
  hop: 1,
  breathe: .8,
);

/// Tristeza: alegria al fondo del todo (puchero hondo y cejas marcadas), la
/// mirada al suelo —la cara entera baja con `gaze`— y el cuerpo un poco
/// aplastado, como hundido. Mirar abajo es lo contrario de la mirada apartada
/// del enfado: son las dos caras de alegria negativa y tenian que separarse
/// por algo que se vea desde lejos.
const TamaPose _sad = TamaPose(
  joy: -1,
  gaze: Offset(0, .8),
  squash: .16,
  tilt: -.05,
  sway: -.4,
  breathe: -.5,
);

/// Sueno: `doze` alto, que ademas de bajar los parpados dispara las zetas del
/// pintor (a partir de .6), y la boca a medio abrir de bostezo.
const TamaPose _sleepy = TamaPose(
  joy: .15,
  doze: .95,
  mouthOpen: .62,
  squash: .22,
  tilt: .13,
  sway: .18,
  breathe: .9,
);

/// Saludo: el brazo arriba del todo. Un Tama sin brazos (la variante 3) no
/// puede saludar, y no hay forma de arreglarlo desde la pose; para esos el
/// ladeo, el impulso lateral y el saltito siguen diciendo "hola".
const TamaPose _wave = TamaPose(
  joy: .62,
  armWave: 1,
  tilt: .12,
  lean: 1.8,
  hop: 2.5,
  mouthOpen: .3,
  sway: .45,
);

/// Un sticker ya puesto: el Tama con su cara, quieto.
///
/// No se anima nunca, ni siquiera sin movimiento reducido: un sticker es una
/// foto, y ademas una conversacion puede tener decenas en pantalla. Sin ticker
/// no hay nada que respetar de [IbashoSkin.reducedMotion] aqui.
class TamaSticker extends StatelessWidget {
  const TamaSticker({
    super.key,
    required this.look,
    required this.face,
    required this.size,
    this.name,
  });

  final TamaLook look;
  final StickerFace face;

  /// Lado de la caja del dibujo. El pie del nombre va aparte, debajo.
  final double size;

  /// Nombre del Tama. Si viene, va debajo en pequeno.
  final String? name;

  @override
  Widget build(BuildContext context) {
    // Sin sombra de contacto: un sticker es un recorte que flota sobre la
    // burbuja, no una figura de pie sobre el suelo del entorno.
    final art = Semantics(
      image: true,
      label: name,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(size),
          painter: TamaPainter(
            look: look,
            pose: poseForFace(face),
            shadow: false,
          ),
        ),
      ),
    );
    if (name == null) return art;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        art,
        const SizedBox(height: 4),
        // El nombre ya lo anuncia la imagen de arriba: aqui solo se dibuja.
        ExcludeSemantics(
          child: SizedBox(
            width: size,
            child: Text(
              name!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Ty.caption,
            ),
          ),
        ),
      ],
    );
  }
}

/// El nombre de una cara en el idioma de la cuenta.
String stickerFaceLabel(L l, StickerFace face) => switch (face) {
      StickerFace.happy => l.stickerFaceHappy,
      StickerFace.wink => l.stickerFaceWink,
      StickerFace.surprised => l.stickerFaceSurprised,
      StickerFace.angry => l.stickerFaceAngry,
      StickerFace.love => l.stickerFaceLove,
      StickerFace.sad => l.stickerFaceSad,
      StickerFace.sleepy => l.stickerFaceSleepy,
      StickerFace.wave => l.stickerFaceWave,
    };
