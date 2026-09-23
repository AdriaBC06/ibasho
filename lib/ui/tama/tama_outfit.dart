// Ibasho — los premios puestos en un Tama: donde va cada uno y como se pinta.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../backend/prizes.dart';
import '../../backend/tama.dart';
import 'tama_painter.dart';

/// Los dibujos de los premios, ya leidos. Cada SVG se lee una vez, la primera
/// que un Tama lo necesita; mientras tanto no se pinta, y al llegar avisa para
/// que los Tamas que lo esperaban se repinten.
class PrizeArt extends ChangeNotifier {
  PrizeArt._();

  static final PrizeArt instance = PrizeArt._();

  final Map<String, PictureInfo> _ready = <String, PictureInfo>{};
  final Set<String> _loading = <String>{};

  /// El dibujo de [asset], o `null` si aun no esta (y entonces se pide).
  PictureInfo? of(String asset) {
    final hit = _ready[asset];
    if (hit != null || _loading.contains(asset)) return hit;
    _loading.add(asset);
    vg.loadPicture(SvgAssetLoader(asset), null).then((info) {
      _ready[asset] = info;
      notifyListeners();
    }, onError: (Object e) {
      debugPrint('Ibasho: no se ha podido leer el premio $asset ($e)');
    });
    return null;
  }

  /// Lee de antemano los dibujos de [items] (las dos partes, si las tienen) y
  /// espera a que esten.
  Future<void> preload(Iterable<PrizeItem> items) async {
    await Future.wait([
      for (final item in items)
        for (final asset in [item.asset, ?item.frontAsset])
          if (!_ready.containsKey(asset))
            vg.loadPicture(SvgAssetLoader(asset), null).then((info) => _ready[asset] = info),
    ]);
    notifyListeners();
  }
}

/// Una pieza colocada: la caja en el lienzo de 100x100 del Tama y si va en
/// espejo (el pie izquierdo es la zapatilla derecha volteada).
typedef PrizeBox = ({Rect rect, bool flip});

typedef _Place = List<PrizeBox> Function(TamaLook look, TamaBody body);

List<PrizeBox> _one(Rect rect) => [(rect: rect, flip: false)];

/// Por donde empieza el pelo: un poco por debajo de la coronilla, pero nunca
/// encima de los ojos.
double _hairline(TamaLook look, TamaBody body, double frac) {
  final f = TamaFace.of(look, body);
  final r = body.bounds;
  return math.min(r.top + r.height * frac, f.eyeY - f.eyeR - 2);
}

/// Un gorro que apoya en la cabeza: [band] es la altura del borde en el SVG y
/// [left]..[right] lo que mide ahi. Se escala al ancho de la cabeza por [fit],
/// pero lo que sube por encima del borde no pasa de [tall] cuerpos de alto,
/// para no taparle los ojos a un Tama chato, ni se sale del lienzo por arriba.
_Place _hat({
  required Size view,
  required double band,
  required double left,
  required double right,
  required double frac,
  double fit = 1.04,
  required double tall,
}) =>
    (look, body) {
      final r = body.bounds;
      final y = _hairline(look, body, frac);
      final byWidth = body.halfWidthAt(y) * 2 * fit / (right - left);
      final byHeight = r.height * tall / band;
      final byRoom = (y - 1) / band;
      final k = math.min(math.min(byWidth, byHeight), byRoom);
      final mid = (left + right) / 2;
      return _one(Rect.fromLTWH(r.center.dx - mid * k, y - band * k, view.width * k, view.height * k));
    };

/// Algo que va sobre los ojos: ojos en (35, [eyeY]) y (65, [eyeY]) del SVG y
/// agujeros de [hole] de medio alto. Se estira a lo ancho con la separacion
/// de los ojos y a lo alto con su tamaño, asi los agujeros caen encima.
_Place _overEyes(Size view, double eyeY, double hole) => (look, body) {
      final f = TamaFace.of(look, body);
      final kx = f.eyeDx * 2 / 30;
      final ky = (f.eyeR * 1.3 / hole).clamp(kx * .75, kx * 1.35);
      return _one(Rect.fromLTWH(
          f.centre.dx - 50 * kx, f.eyeY - eyeY * ky, view.width * kx, view.height * ky));
    };

/// Donde va la nariz: entre los ojos y la boca.
Offset _nose(TamaLook look, TamaBody body, [double t = .5]) {
  final f = TamaFace.of(look, body);
  return Offset(f.centre.dx, f.eyeY + (f.mouthY - f.eyeY) * t);
}

/// Unos auriculares: los cascos, en [cups] del SVG, van a los lados de la
/// cabeza y el arco pasa por encima de la coronilla. La cabeza ocupa de x=14
/// a 86.
_Place _headset(Size view, double cups) => (look, body) {
      final r = body.bounds;
      final y = r.top + r.height * .42;
      final kx = body.halfWidthAt(y) * 2 / 72;
      final ky = ((y - (r.top - 2)) / (cups - 6)).clamp(kx * .6, kx * 1.4);
      return _one(Rect.fromLTWH(r.center.dx - 50 * kx, y - cups * ky, view.width * kx, view.height * ky));
    };

/// Algo que flota sobre la cabeza (aureola, nube): el punto [base] del SVG,
/// en el centro, queda [gap] por encima de la coronilla. Mide [size] cuerpos
/// de ancho, entre [min] y [max], y nunca se sale del lienzo por arriba.
_Place _floating(Size view, double base, double gap, double size, double min, double max) =>
    (look, body) {
      final r = body.bounds;
      final y = r.top - gap;
      final k = math.min((r.width * size).clamp(min, max) / view.width, (y - 1) / base);
      return _one(Rect.fromLTWH(r.center.dx - view.width / 2 * k, y - base * k, view.width * k, view.height * k));
    };

/// Algo de pie en el suelo a su derecha (las bebidas): la base pisa en [base]
/// del SVG, y mide como la botella.
_Place _standing(Size view, double base) => (look, body) {
      final r = body.bounds;
      final k = (r.height * .7).clamp(24.0, 34.0) / base;
      return _one(Rect.fromLTWH(
          r.right - 3, TamaPainter.floor + .6 - base * k, view.width * k, view.height * k));
    };

/// Algo que lleva en la mano: [grip] es el punto del SVG que va pegado a su
/// costado, a [at] de su alto (0 es la coronilla), a su derecha o a su
/// izquierda. El dibujo mide [size] cuerpos de alto, entre [min] y [max].
_Place _held(
  Size view,
  Offset grip, {
  required bool right,
  double at = .62,
  double size = .75,
  double min = 22,
  double max = 34,
}) =>
    (look, body) {
      final r = body.bounds;
      final y = r.top + r.height * at;
      final side = body.halfWidthAt(y);
      final x = r.center.dx + (right ? side : -side);
      final k = (r.height * size).clamp(min, max) / view.height;
      return _one(Rect.fromLTWH(x - grip.dx * k, y - grip.dy * k, view.width * k, view.height * k));
    };

/// Algo que abraza el cuerpo entero (mochila, capa): [inView] es donde va el
/// cuerpo en el SVG, y se estira para que caiga justo encima.
_Place _aroundBody(Size view, Rect inView) => (look, body) {
      final r = body.bounds;
      final kx = r.width / inView.width;
      final ky = r.height / inView.height;
      return _one(Rect.fromLTWH(
          r.left - inView.left * kx, r.top - inView.top * ky, view.width * kx, view.height * ky));
    };

/// Lo que va a la espalda o alrededor como las alas: cuerpo de x=30 a 90 en
/// un SVG de 120x100 y anclaje en (60, 50), con tope al ancho.
List<PrizeBox> _wings(TamaLook look, TamaBody body) {
  final r = body.bounds;
  final k = math.min(r.width, 58) / 60;
  final at = Offset(r.center.dx, r.top + r.height * .42);
  return _one(Rect.fromLTWH(at.dx - 60 * k, at.dy - 50 * k, 120 * k, 100 * k));
}

/// La altura del cuello: bajo la boca, pero dentro del cuerpo.
double _neck(TamaLook look, TamaBody body, double below) {
  final f = TamaFace.of(look, body);
  final r = body.bounds;
  return math.min(math.max(f.mouthY + below, r.top + r.height * .68), r.bottom - 6);
}

/// Como se coloca cada premio, por su id. Las medidas son las del SVG de su
/// plantilla en `tool/prizes/templates/`.
final Map<String, _Place> _places = <String, _Place>{
  'cap': _hat(view: const Size(100, 100), band: 70, left: 18, right: 82, frac: .15, tall: .75),
  'afro': _hat(view: const Size(100, 100), band: 74, left: 20, right: 80, frac: .26, fit: 1.08, tall: .66),
  'beanie': _hat(view: const Size(100, 100), band: 72, left: 16, right: 84, frac: .18, tall: .6),
  'beret': _hat(view: const Size(100, 60), band: 48, left: 21, right: 79, frac: .12, fit: .96, tall: .38),
  'crown': _hat(view: const Size(100, 72), band: 62, left: 16, right: 84, frac: .1, fit: .72, tall: .5),
  'hachimaki': (look, body) {
    final r = body.bounds;
    final y = _hairline(look, body, .24);
    final k = body.halfWidthAt(y) * 2 / 100;
    return _one(Rect.fromLTWH(r.center.dx - 60 * k, y - 22 * k, 120 * k, 44 * k));
  },
  'headphones': _headset(const Size(100, 80), 52),
  'gamer_headset': _headset(const Size(100, 80), 52),
  'cat_headset': _headset(const Size(100, 84), 56),
  'cat_headset_rgb': _headset(const Size(100, 84), 56),
  'top_hat': _hat(view: const Size(100, 100), band: 86, left: 20, right: 80, frac: .12, fit: .85, tall: .8),
  'hard_hat': _hat(view: const Size(100, 100), band: 72, left: 16, right: 84, frac: .18, fit: 1.02, tall: .55),
  'frog_hat': _hat(view: const Size(100, 100), band: 72, left: 16, right: 84, frac: .2, tall: .6),
  'chef_hat': _hat(view: const Size(100, 100), band: 76, left: 22, right: 78, frac: .12, fit: .9, tall: .8),
  'witch_hat': _hat(view: const Size(100, 100), band: 82, left: 24, right: 76, frac: .12, fit: 1, tall: .85),
  'wizard_hat': _hat(view: const Size(100, 100), band: 82, left: 24, right: 76, frac: .12, fit: 1, tall: .85),
  'nightcap': _hat(view: const Size(100, 100), band: 72, left: 16, right: 84, frac: .18, tall: .55),
  'flower_crown': _hat(view: const Size(100, 44), band: 30, left: 12, right: 88, frac: .14, fit: 1, tall: .3),
  'kitsune': _hat(view: const Size(100, 100), band: 70, left: 18, right: 82, frac: .18, tall: .6),
  'viking': _hat(view: const Size(100, 100), band: 70, left: 20, right: 80, frac: .16, fit: 1.02, tall: .6),
  'kabuto': _hat(view: const Size(100, 100), band: 72, left: 18, right: 82, frac: .16, tall: .7),
  'sombrero': _hat(view: const Size(120, 70), band: 56, left: 40, right: 80, frac: .14, fit: .95, tall: .5),
  'devil_horns': _hat(view: const Size(100, 50), band: 44, left: 14, right: 86, frac: .1, fit: .95, tall: .4),
  'crown_rgb': _hat(view: const Size(100, 72), band: 62, left: 16, right: 84, frac: .1, fit: .72, tall: .5),
  'leaf': (look, body) {
    // Un brote que nace en la coronilla.
    final r = body.bounds;
    final k = math.min((r.width * .4).clamp(16.0, 26.0) / 60, (r.top + 3 - 1) / 57);
    return _one(Rect.fromLTWH(r.center.dx - 30 * k, r.top + 3 - 57 * k, 60 * k, 60 * k));
  },
  'bow': (look, body) {
    // El nudo va en la cabeza, un poco a su izquierda.
    final r = body.bounds;
    final k = (r.width * .55).clamp(24.0, 40.0) / 80;
    final at = Offset(r.center.dx + r.width * .2, math.max(r.top + r.height * .12, 26 * k + 1));
    return _one(Rect.fromLTWH(at.dx - 40 * k, at.dy - 26 * k, 80 * k, 50 * k));
  },
  'halo': _floating(const Size(80, 36), 18, 4, .7, 26, 40),
  'halo_rgb': _floating(const Size(80, 36), 18, 4, .7, 26, 40),
  'rainbow_cloud': _floating(const Size(100, 64), 60, 1, .95, 34, 56),
  'hood': (look, body) {
    final f = TamaFace.of(look, body);
    final r = body.bounds;
    // La abertura (96 de ancho) abraza el cuerpo y la frente de la capucha
    // queda justo encima de los ojos; la tela no pasa de la barriga, que en
    // un Tama chato es lo que manda.
    final kx = r.width * 1.02 / 96;
    final top = r.top - 3;
    final ky = math
        .min(((f.eyeY - f.eyeR - 3) - top) / 18, (r.top + r.height * .85 - top) / 78)
        .clamp(kx * .45, kx * 1.2);
    return _one(Rect.fromLTWH(r.center.dx - 60 * kx, top - 2 * ky, 120 * kx, 100 * ky));
  },
  'mask': _overEyes(const Size(100, 60), 30, 8),
  'rgb_shades': _overEyes(const Size(100, 40), 20, 10),
  'glasses': _overEyes(const Size(100, 40), 20, 9),
  'shutter_shades': _overEyes(const Size(100, 40), 20, 10),
  'groucho': (look, body) {
    final f = TamaFace.of(look, body);
    final kx = f.eyeDx * 2 / 30;
    final ky = ((f.mouthY - f.eyeY) / 36).clamp(kx * .6, kx * 1.5);
    return _one(Rect.fromLTWH(f.centre.dx - 50 * kx, f.eyeY - 22 * ky, 100 * kx, 70 * ky));
  },
  'clown_nose': (look, body) {
    final f = TamaFace.of(look, body);
    final d = math.max(f.eyeR * 2.4, 10.0) * 40 / 32;
    return _one(Rect.fromCenter(center: _nose(look, body), width: d, height: d));
  },
  'bandage': (look, body) {
    final f = TamaFace.of(look, body);
    final k = f.eyeDx * 2 * 1.05 / 52;
    return _one(Rect.fromCenter(center: _nose(look, body, .4), width: 60 * k, height: 30 * k));
  },
  'bowtie': (look, body) {
    final f = TamaFace.of(look, body);
    final r = body.bounds;
    final y = math.min(math.max(f.mouthY + 7, r.top + r.height * .72), r.bottom - 6);
    final k = r.width * .36 / 60;
    return _one(Rect.fromCenter(center: Offset(r.center.dx, y), width: 60 * k, height: 34 * k));
  },
  'scarf': (look, body) {
    final r = body.bounds;
    final y = _neck(look, body, 5);
    // La vuelta (60 de ancho) cubre el cuello de lado a lado; en un Tama
    // chato no crece tanto que las puntas lleguen al suelo.
    final k = math.min(body.halfWidthAt(y) * 2 * 1.04 / 60, (TamaPainter.floor - y + 6) / 30);
    return _one(Rect.fromLTWH(r.center.dx - 35 * k, y - 16 * k, 70 * k, 46 * k));
  },
  'dollar_chain': (look, body) {
    final f = TamaFace.of(look, body);
    final r = body.bounds;
    final y = math.min(f.mouthY + 3, r.bottom - 14);
    // La cadena sale de los costados y el medallon no pasa del suelo.
    final k = math
        .min(math.max(body.halfWidthAt(y) * 2 * .9, 34) / 72, (TamaPainter.floor - y) / 48)
        .clamp(.3, r.width * .5 / 26);
    return _one(Rect.fromLTWH(r.center.dx - 40 * k, y - 4 * k, 80 * k, 52 * k));
  },
  'sneakers': (look, body) {
    final r = body.bounds;
    final k = r.width * .44 / 60;
    return [
      for (final side in const [-1.0, 1.0])
        (
          rect: Rect.fromLTWH(r.center.dx + side * r.width * .25 - 30 * k,
              TamaPainter.floor + .6 - 32 * k, 60 * k, 34 * k),
          flip: side < 0,
        ),
    ];
  },
  'swim_ring': (look, body) {
    final r = body.bounds;
    final y = r.top + r.height * .66;
    // El agujero (68 de ancho) abraza la cintura; a lo alto no pasa de lo
    // que mide el cuerpo, para que en un Tama chato no le tape la cara.
    final kx = body.halfWidthAt(y) * 2 * 1.04 / 68;
    final ky = math.min(kx, r.height * .8 / 44).clamp(kx * .45, kx);
    return _one(Rect.fromLTWH(r.center.dx - 60 * kx, y - 30 * ky, 120 * kx, 60 * ky));
  },
  // A la derecha: bebidas en el suelo y lo que empuna.
  'bottle': _standing(const Size(30, 70), 68),
  'energy': _standing(const Size(30, 70), 68),
  'boba': _standing(const Size(36, 70), 68),
  'pickaxe': _held(const Size(72, 72), const Offset(12, 60), right: true, size: .8, min: 26, max: 38),
  'sword': _held(const Size(72, 72), const Offset(12, 56), right: true, size: .8, min: 26, max: 38),
  'microphone': _held(const Size(44, 64), const Offset(8, 60), right: true, at: .72, size: .8, min: 24, max: 34),
  'cursor': (look, body) {
    // Flota arriba a su derecha y la punta le senala el hombro.
    final r = body.bounds;
    final y = r.top + r.height * .3;
    final k = (r.height * .8).clamp(32.0, 40.0) / 60;
    final x = r.center.dx + body.halfWidthAt(y) + 1;
    return _one(Rect.fromLTWH(x - 12 * k, y - 12 * k, 50 * k, 60 * k));
  },
  // A la izquierda: lo que sujeta.
  'taco': _held(const Size(68, 54), const Offset(60, 38), right: false, size: .5, min: 16, max: 24),
  'balloon': _held(const Size(50, 100), const Offset(46, 96), right: false, at: .66, size: 1.2, min: 40, max: 56),
  'uchiwa': _held(const Size(44, 64), const Offset(36, 60), right: false, size: .8, min: 24, max: 34),
  'lantern': _held(const Size(50, 80), const Offset(46, 72), right: false, at: .7, size: 1.1, min: 38, max: 48),
  'fish_bag': _held(const Size(44, 64), const Offset(38, 5), right: false, at: .55, size: .9, min: 28, max: 36),
  'kendama': _held(const Size(50, 70), const Offset(36, 67), right: false, at: .7, size: 1, min: 32, max: 40),
  'controller': _held(const Size(72, 52), const Offset(70, 30), right: false, at: .6, size: .5, min: 18, max: 26),
  // Detras y alrededor.
  'randoseru': _aroundBody(const Size(120, 100), const Rect.fromLTRB(30, 20, 90, 90)),
  'cape': _aroundBody(const Size(120, 100), const Rect.fromLTRB(30, 20, 90, 90)),
  'angel_wings': _wings,
  'rgb_wings': _wings,
  'fairies': _wings,
};

/// Las cajas que ocupa [item] en un Tama con este aspecto.
List<PrizeBox> prizeBoxes(PrizeItem item, TamaLook look, TamaBody body) =>
    _places[item.prize.id]?.call(look, body) ?? const <PrizeBox>[];

/// Lo que lleva puesto [look], ya resuelto: se salta lo que esta version no
/// conoce.
List<PrizeItem> wornItems(TamaLook look) => [
      ?prizeItem(look.outfit.hat),
      for (final k in look.outfit.accessories) ?prizeItem(k),
    ];

/// Si lleva algo que sustituye a los pies (las zapatillas).
bool hidesFeet(TamaLook look) => wornItems(look).any((i) => i.prize.slot == PrizeSlot.feet);

/// Pinta lo que lleve puesto en [slots], en el lienzo de 100x100 del Tama y
/// dentro de su transformacion, asi salta, se inclina y se aplasta con el. Con
/// [front] pinta la parte de delante de los premios que van en dos partes.
void paintOutfit(Canvas canvas, TamaLook look, TamaBody body, Set<PrizeSlot> slots,
    {bool front = false}) {
  for (final item in wornItems(look)) {
    if (!slots.contains(item.prize.slot)) continue;
    final asset = front ? item.frontAsset : item.asset;
    if (asset == null) continue;
    final art = PrizeArt.instance.of(asset);
    if (art == null) continue;
    for (final box in prizeBoxes(item, look, body)) {
      canvas.save();
      canvas.translate(box.rect.left, box.rect.top);
      canvas.scale(box.rect.width / art.size.width, box.rect.height / art.size.height);
      if (box.flip) {
        canvas.translate(art.size.width, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawPicture(art.picture);
      canvas.restore();
    }
  }
}
