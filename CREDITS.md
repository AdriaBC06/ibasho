# Créditos

Ibasho se apoya en trabajo libre. Aquí está cada asset que se distribuye con la
app, con su autor, su licencia y de dónde sale. La misma lista se muestra dentro
de la app en **Ajustes → créditos** (`lib/core/credits.dart`); si añades un asset,
toca los dos sitios.

Regla de la casa: solo **CC0** o **CC BY** para audio, **SIL OFL** para
tipografías. Nada con cláusula NC o ND (incompatible con GPL-3.0) y ningún audio
original de Nintendo.

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
(dominio público). Se puede regenerar con `python3 tool/gen_audio.py`.

| Título | Archivo | Autor | Licencia |
|---|---|---|---|
| plaza (con ritmo, 120 bpm, bucle de 32 s) | `assets/audio/bgm/plaza.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| calma (ambiente, bucle de 64 s, pista por defecto) | `assets/audio/bgm/calma.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| aurora (ambiente, bucle de 80 s) | `assets/audio/bgm/aurora.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| brisa (ambiente, bucle de 64 s) | `assets/audio/bgm/brisa.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
| noche (ambiente, bucle de 64 s) | `assets/audio/bgm/noche.ogg` | Adrià Bonnin Catalán | CC0 1.0 |
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
