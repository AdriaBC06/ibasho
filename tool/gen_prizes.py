#!/usr/bin/env python3
# Ibasho — generador de los premios del gacha (gorros y accesorios).
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Cada premio se dibuja una vez como plantilla en tool/prizes/templates/ con
# los colores como huecos, y este script saca una variante por color en
# assets/prizes/. Asi un gorro de cuatro colores es un solo dibujo.
#
# Huecos de una plantilla, para cada color con nombre (p. ej. `main`):
#   {main}        el color base
#   {main.light}  aclarado hacia el blanco (arriba del degradado de plastico)
#   {main.deep}   oscurecido hacia el azul noche (abajo del degradado)
#   {main.edge}   el filo: el mismo tono mucho mas oscuro, nunca negro
#
# Una variante puede traer su propio dibujo con la clave `template` (la
# botella de agua y la de cola son el mismo premio con distinta forma).
#
# Si junto a una plantilla hay otra con `_front` (randoseru_front.svg), sale
# tambien `<id>_<variante>_front.svg`: la parte que va delante del cuerpo
# (las correas, la mitad de delante del flotador). Tiene el mismo viewBox.
#
# La rareza, el sitio donde va y como se coloca viven en la app:
# lib/backend/prizes.dart y lib/ui/tama/tama_outfit.dart.
#
# Uso:  python3 tool/gen_prizes.py

import json
import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "tool", "prizes")
OUT = os.path.join(ROOT, "assets", "prizes")

# Los mismos tonos que `T.shellTop` y `T.dusk`, y las mismas mezclas que
# `paintPlastic` en channel_art.dart.
WHITE = (0xFF, 0xFF, 0xFF)
DUSK = (0x0B, 0x22, 0x30)
MIX = {"light": (WHITE, .35), "deep": (DUSK, .18), "edge": (DUSK, .45)}


def parse(hex_):
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def fmt(c):
    return "#%02X%02X%02X" % c


def fill(template, colors):
    def sub(m):
        name, _, tone = m.group(1).partition(".")
        base = parse(colors[name])
        if not tone:
            return fmt(base)
        target, t = MIX[tone]
        return fmt(lerp(base, target, t))

    return re.sub(r"\{([a-z0-9]+(?:\.[a-z]+)?)\}", sub, template)


def main():
    with open(os.path.join(SRC, "prizes.json"), encoding="utf-8") as f:
        prizes = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    count = 0
    for prize in prizes:
        for variant, colors in prize["variants"].items():
            colors = dict(colors)
            source = colors.pop("template", prize.get("template"))
            front = source.replace(".svg", "_front.svg")
            parts = [(source, f"{prize['id']}_{variant}.svg")]
            if os.path.exists(os.path.join(SRC, "templates", front)):
                parts.append((front, f"{prize['id']}_{variant}_front.svg"))
            for src, name in parts:
                with open(os.path.join(SRC, "templates", src), encoding="utf-8") as f:
                    svg = fill(f.read(), colors)
                # Un hueco sin rellenar sale negro en pantalla: mejor parar aqui.
                left = re.search(r"\{[^}]*\}", svg)
                if left:
                    raise SystemExit(f"{name}: hueco sin rellenar {left.group(0)}")
                with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
                    f.write(svg)
                count += 1
    print(f"{count} dibujos en assets/prizes/")


if __name__ == "__main__":
    main()
