# Créditos

Ibasho se apoya en trabajo libre. Aquí está cada asset que se distribuye con la
app, con su autor, su licencia y de dónde sale. La misma lista se muestra dentro
de la app en **Ajustes → créditos** (`lib/core/credits.dart`); si añades un asset,
toca los dos sitios.

Regla de la casa: solo **CC0** o **CC BY** para audio, **SIL OFL** para
tipografías. Nada con cláusula NC o ND (incompatible con GPL-3.0) y ningún audio
original de Nintendo. **Única excepción:** las canciones de Odori, que no son
código ni forman parte de la obra GPL y se licencian aparte (ver más abajo).

## Tamas

Los Tamas no usan ningún asset: su dibujo (`lib/ui/tama/tama_painter.dart`) y
su voz (`lib/audio/tama_voice.dart`) son código propio de Adrià Bonnin Catalán,
bajo la misma licencia GPL-3.0-or-later que el resto de Ibasho.

## Tipografías

| Título | Autor | Licencia | URL | Uso |
|---|---|---|---|---|
| Zen Kaku Gothic New (Regular, Medium, Bold) | Yoshimichi Ohira | SIL Open Font License 1.1 | https://fonts.google.com/specimen/Zen+Kaku+Gothic+New | Toda la interfaz. Kana y kanji completos. |
| M PLUS Rounded 1c (Medium, Bold) | Coji Morishita, The M+ Fonts Project | SIL Open Font License 1.1 | https://github.com/coz-m/MPLUS_FONTS | Reloj, números grandes y logotipo. |

Los textos de licencia están en `assets/fonts/LICENSES/`.

## Audio

### Música propia

Original, sintetizada por `tool/gen_audio.py` y publicada bajo **CC0 1.0**
(dominio público). Se puede regenerar con `python3 tool/gen_audio.py`; la de
Nihongo, con `python3 tool/gen_nihongo_music.py`.

| Título | Archivo | Autor | Licencia |
|---|---|---|---|
| plaza (con ritmo, 120 bpm, bucle de 32 s) | `assets/audio/bgm/plaza.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| hanami (con ritmo, 112 bpm, bucle de 34 s; suena jugando a Nihongo) | `assets/audio/bgm/hanami.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| sumi (con ritmo, 78 bpm, bucle de 49 s; suena en el menú de Nihongo) | `assets/audio/bgm/sumi.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| calma (ambiente, bucle de 64 s, pista por defecto) | `assets/audio/bgm/calma.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| aurora (ambiente, bucle de 80 s) | `assets/audio/bgm/aurora.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| brisa (ambiente, bucle de 64 s) | `assets/audio/bgm/brisa.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| noche (ambiente, bucle de 64 s) | `assets/audio/bgm/noche.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| nana (premio del gacha, N; nana en 3 tiempos, bucle de 72 s) | `assets/audio/bgm/nana.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| carrillon (premio del gacha, N; caja de música, bucle de 48 s) | `assets/audio/bgm/carrillon.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| lofi (premio del gacha, R; groove suave a 76 bpm, bucle de 25,3 s) | `assets/audio/bgm/lofi.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| feria (premio del gacha, SR; con ritmo a 138 bpm, bucle de 27,8 s) | `assets/audio/bgm/feria.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| abrigo (premio del gacha, UR; pad de cuerdas cálido, bucle de 88 s) | `assets/audio/bgm/abrigo.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| cenit (premio del gacha, ∞; contrapunto a dos voces, bucle de 96 s) | `assets/audio/bgm/cenit.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| tick · open · back · error · chime (efectos) | `assets/audio/sfx/*.wav` | Adrià Bonnin Catalán | CC0 1.0 |

Cada pista está además en MP3 (`.mp3`, VBR calidad 2) al lado de su `.ogg`, con
la misma licencia y el mismo contenido: es lo que suena en Windows, donde el
sistema no tiene decodificador de Ogg Vorbis. Linux y Android siguen usando los
`.ogg` originales.

### Música de terceros

Descargada de OpenGameArt. La licencia se ha comprobado en la página de cada
pista antes de incluirla. **Cambios:** convertida a Ogg Vorbis (calidad 5,
44,1 kHz estéreo) y nivelada en sonoridad a unos −15,5 LUFS (EBU R128). No se
ha alterado nada más.

| Título | Archivo | Autor | Licencia | Origen |
|---|---|---|---|---|
| Bossa Nova | `assets/audio/bgm/bossa.ogg` | Joth | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | https://opengameart.org/content/bossa-nova |

### Odori: canciones y voces

Las nueve canciones de Odori (Tamagoyaki, Hanabi no Ato, Neko no Basu, Ame no Hi
no Kasa, Tsukimi Dango, Kaeri Michi, Ibasho, Yakō y Hoshikuzu Dash), con su
música, sus letras (`docs/letras/`) y sus partituras, son de Adrià Bonnin
Catalán, generadas con `tool/gen_odori_music.py`, `tool/odori_canciones.py` y
`tool/odori_voices.py` (esos scripts sí son GPL-3.0).

**Todo lo que hay en `assets/odori/` se licencia bajo
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/), no bajo la
GPL-3.0**, instrumentales incluidas, porque las voces de Teto, Kiritan y
Zundamon solo permiten uso no comercial. Ibasho no se vende ni da dinero; las
monedas del Yatai son del juego y no se compran.

La licencia CC cubre la parte de Adrià. **La voz de cada versión conserva
además las condiciones de su banco**, que siguen valiendo para quien reutilice
los archivos:

- **Teto:** nada comercial; nada que ofenda o dañe a terceros; no hacerse pasar
  por su autora.
- **NEUTRINO (Kiritan, Zundamon, Merrow):**
  - prohibido usar el audio para entrenar modelos o como entrada de conversión
    de voz;
  - prohibido usarlo como librería de sonidos o de samples;
  - nada político, religioso, violento ni difamatorio.
- **Kiritan y Zundamon:** además, la guía de personajes de zunko.jp.

| Voz | Autor | Licencia | Dónde sale |
|---|---|---|---|
| NIT SONG070 F001 (Sinsy) | Nagoya Institute of Technology (HTS Working Group) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). **Cambios:** su f0 se sustituye por una curva de la partitura y se resintetiza con WORLD; `hoshikuzu_voz_b` lleva además los formantes ×1,12. | Hoshikuzu Dash (`_voz`, `_voz_b`), `yako_*_sinsy` |
| Kasane Teto 重音テト (JP y EN) | Voz: 小山乃舞世. Diseño del personaje: 線. Círculo oficial: ツインドリル (TWINDRILL). | [Condiciones del banco de voz](https://kasaneteto.jp/guideline/vltu.html): no comercial. Kasane Teto © TWINDRILL. | Todas las `*_teto` |
| Tohoku Kiritan 東北きりたん | Personaje: 東北ずん子・ずんだもんプロジェクト (SSS LLC.). Banco NEUTRINO: STUDIO NEUTRINO. | [zunko.jp](https://zunko.jp/guideline.html): no comercial, sin trámite | `yako_*_kiritan` |
| Zundamon ずんだもん | Igual que Kiritan | Igual que Kiritan | `yako_*_zundamon` |
| Merrow めろう | STUDIO NEUTRINO | Licencia de la librería NEUTRINO: uso comercial y no comercial, crédito opcional | `yako_*_merrow` |

El entrenamiento del banco de Kiritan usa el 東北きりたん歌唱データベース.

**Herramientas usadas para cantar** (ninguna va dentro de la app):

| Herramienta | Autor | Licencia | URL |
|---|---|---|---|
| NEUTRINO | SHACHI (STUDIO NEUTRINO) | Freeware; el audio que genera sigue las condiciones de cada banco | https://studio-neutrino.com |
| Sinsy / pysinsy | Sinsy working group, Nagoya Institute of Technology | Modified BSD | https://sinsy.sourceforge.net |
| WORLD / pyworld | Masanori Morise; pyworld, Jeremy Hsu y colaboradores | Modified BSD (WORLD), MIT (pyworld) | https://github.com/mmorise/World |

### Reservado (no se empaqueta en la app)

Guardadas en `reserved/audio/bgm/` para usos futuros. No están en
`pubspec.yaml`, así que no forman parte del build. Mismos cambios que arriba.

| Título | Archivo | Autor | Licencia | Origen |
|---|---|---|---|---|
| Funky Menu Loop | `reserved/audio/bgm/funky.ogg` | iamoneabe | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | https://opengameart.org/content/funky-menu-loop |
| Feel Good Island Loop | `reserved/audio/bgm/island.ogg` | AntumDeluge | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) (también OGA-BY 3.0; se usa la CC0) | https://opengameart.org/content/feel-good-island-loop |
| Peace At Last (Loop) | `reserved/audio/bgm/peace.ogg` | Trex0n | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | https://opengameart.org/content/peace-at-last-loop |

## Software

| Paquete | Autor | Licencia | URL |
|---|---|---|---|
| Flutter | The Flutter Authors | BSD 3-Clause | https://flutter.dev |
| Riverpod | Remi Rousselet | MIT | https://riverpod.dev |
| audioplayers | Blue Fire | MIT | https://pub.dev/packages/audioplayers |
| pointycastle | The Legion of the Bouncy Castle | MIT | https://pub.dev/packages/pointycastle |
| url_launcher | The Flutter Authors | BSD 3-Clause | https://pub.dev/packages/url_launcher |
| flutter_secure_storage | Julian Steenbakker | BSD 3-Clause | https://pub.dev/packages/flutter_secure_storage |
| timezone (base de datos IANA embebida) | timezone project authors | BSD 2-Clause | https://pub.dev/packages/timezone |
| http, intl, crypto, path_provider | Dart / Flutter team | BSD 3-Clause | https://pub.dev |

## Ibasho

Ibasho se publica bajo la **GNU General Public License, versión 3 o posterior**.
Ver `LICENSE`.
Las canciones de Odori (`assets/odori/`) son la excepción: CC BY-NC 4.0, como
se explica arriba.
