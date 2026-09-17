// Ibasho — las 512 palabras de la frase de respaldo.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

/// Alfabeto de la frase de respaldo: 512 palabras, 9 bits cada una.
///
/// **Esta lista no se toca nunca.** Cambiar, quitar o reordenar una palabra
/// invalida todas las frases de respaldo ya entregadas, y con ellas el
/// historial cifrado que protegen. `test/wordlist_test.dart` comprueba las
/// propiedades de abajo para que ningun cambio pase sin darse cuenta.
///
/// Propiedades que cumple y de las que depende el resto del codigo:
/// - exactamente 512 palabras, ordenadas alfabeticamente (busqueda binaria);
/// - solo `a`-`z`, sin tildes ni eñes, de 3 a 8 letras;
/// - las cuatro primeras letras identifican una sola palabra.
const List<String> backupWordlist = <String>[
  'abedul', 'abeja', 'abeto', 'abogado', 'aceite', 'acelga', 'acequia', 'actor',
  'afluente', 'ajo', 'albahaca', 'alcalde', 'aldea', 'alfombra', 'almeja', 'almohada',
  'alpaca', 'altavoz', 'amanecer', 'amapola', 'amarillo', 'anchoa', 'apio', 'arce',
  'ardilla', 'arena', 'armario', 'arroyo', 'arteria', 'artista', 'aurora', 'avellana',
  'avestruz', 'avispa', 'avutarda', 'axila', 'azul', 'babosa', 'bacalao', 'balde',
  'bandeja', 'barba', 'barranco', 'batidora', 'beis', 'berro', 'bigote', 'bisagra',
  'bisonte', 'bizcocho', 'blanco', 'boa', 'boca', 'boj', 'bolsa', 'bombero',
  'bosque', 'botella', 'brazo', 'bronce', 'brote', 'brujo', 'bruma', 'buey',
  'buitre', 'burro', 'caballo', 'cabeza', 'cable', 'cabra', 'cachorro', 'cactus',
  'cadena', 'caja', 'cala', 'caldo', 'calima', 'calle', 'calor', 'cama',
  'camello', 'camino', 'campo', 'canal', 'candado', 'canela', 'cangrejo', 'cantante',
  'caoba', 'capilla', 'capullo', 'caracol', 'carne', 'carta', 'casa', 'cascada',
  'castillo', 'catarata', 'catedral', 'cauce', 'caverna', 'cazador', 'cazo', 'cazuela',
  'cebada', 'cebolla', 'cebra', 'ceja', 'celeste', 'centeno', 'cepillo', 'cerdo',
  'cerebro', 'cerilla', 'cerro', 'cesta', 'chacal', 'charco', 'chinche', 'chopo',
  'chorizo', 'choza', 'chubasco', 'cian', 'cielo', 'ciervo', 'cigarra', 'cilantro',
  'cima', 'cine', 'cintura', 'ciruela', 'cisne', 'ciudad', 'clavel', 'cobra',
  'cocina', 'coco', 'codo', 'col', 'comino', 'conde', 'conejo', 'conserje',
  'convento', 'copa', 'coral', 'cordero', 'corral', 'corteza', 'corzo', 'costa',
  'cotorra', 'crema', 'cuaderno', 'cubo', 'cuchara', 'cuco', 'cuello', 'cuerda',
  'cueva', 'cumbre', 'cura', 'dedo', 'delta', 'dentista', 'desierto', 'diente',
  'diluvio', 'dorado', 'duna', 'duque', 'eclipse', 'elefante', 'embalse', 'enchufe',
  'eneldo', 'ensalada', 'ensenada', 'erizo', 'ermita', 'escalera', 'escoba', 'escriba',
  'escuela', 'espalda', 'espejo', 'espina', 'espuma', 'establo', 'estepa', 'estrecho',
  'fango', 'faro', 'flamenco', 'flan', 'foca', 'frasco', 'fregona', 'frente',
  'fresa', 'galleta', 'gamba', 'gamo', 'ganso', 'garaje', 'garbanzo', 'garganta',
  'garza', 'gato', 'gaviota', 'geranio', 'gimnasio', 'girasol', 'glaciar', 'golfo',
  'goma', 'gorila', 'granate', 'grava', 'grifo', 'grillo', 'gris', 'grulla',
  'gruta', 'guarda', 'guepardo', 'guijarro', 'guisante', 'haba', 'harina', 'helada',
  'helecho', 'heraldo', 'herrero', 'hiena', 'hierba', 'higo', 'higuera', 'hoja',
  'hombro', 'hormiga', 'horno', 'huerta', 'hueso', 'huevo', 'iglesia', 'iguana',
  'ingle', 'iris', 'isla', 'istmo', 'jarra', 'jengibre', 'jilguero', 'jirafa',
  'juez', 'juglar', 'jungla', 'kiwi', 'koala', 'labio', 'ladera', 'lagarto',
  'lago', 'laguna', 'langosta', 'lata', 'laurel', 'lavadora', 'leche', 'lemur',
  'lengua', 'lenteja', 'leopardo', 'librero', 'liebre', 'lila', 'lima', 'limonero',
  'lince', 'linterna', 'lirio', 'llama', 'llano', 'llave', 'lluvia', 'lobo',
  'lodo', 'loma', 'lombriz', 'loro', 'lubina', 'luna', 'maestro', 'magenta',
  'mago', 'maleta', 'malva', 'mango', 'mano', 'manta', 'manzana', 'mar',
  'masa', 'medusa', 'mejilla', 'menta', 'mercado', 'merluza', 'mesa', 'meseta',
  'miel', 'minero', 'mochila', 'mofeta', 'molino', 'monarca', 'monje', 'mono',
  'morado', 'morsa', 'mosca', 'mosquito', 'mostaza', 'muela', 'mula', 'muralla',
  'muro', 'museo', 'musgo', 'muslo', 'nabo', 'naranja', 'nariz', 'nata',
  'natillas', 'negro', 'nevada', 'nevera', 'niebla', 'nieve', 'notario', 'nube',
  'nudillo', 'nuez', 'nutria', 'oasis', 'obispo', 'oca', 'ocre', 'oficina',
  'ojo', 'ola', 'olivo', 'olla', 'ombligo', 'oreja', 'orilla', 'oro',
  'oso', 'ostra', 'oveja', 'pajar', 'palacio', 'palmera', 'paloma', 'pan',
  'papaya', 'papel', 'pared', 'parque', 'parra', 'pasta', 'patata', 'patio',
  'pato', 'pavo', 'pecho', 'peine', 'pelo', 'penumbra', 'pepino', 'pera',
  'percebe', 'perdiz', 'perejil', 'perro', 'persiana', 'pescado', 'pico', 'pie',
  'pila', 'piloto', 'pimienta', 'pino', 'pintor', 'piscina', 'pistacho', 'plancha',
  'plata', 'playa', 'plaza', 'poeta', 'polen', 'polilla', 'pollo', 'polvo',
  'pomelo', 'portero', 'potro', 'pozo', 'pradera', 'presa', 'pueblo', 'puente',
  'puerro', 'pulga', 'pulpo', 'puma', 'pupila', 'queso', 'quiosco', 'radio',
  'rallador', 'rama', 'rana', 'rata', 'rayo', 'regla', 'reina', 'reloj',
  'represa', 'rey', 'ribera', 'risco', 'roble', 'roca', 'rodilla', 'rojo',
  'romero', 'roquedal', 'rosa', 'sabana', 'sal', 'sangre', 'sapo', 'sardina',
  'sastre', 'sauce', 'secadora', 'seco', 'sello', 'selva', 'semilla', 'sendero',
  'sepia', 'seta', 'sierra', 'silla', 'sobre', 'soja', 'sol', 'sopa',
  'sudor', 'suelo', 'taller', 'tarro', 'tarta', 'taxista', 'taza', 'teatro',
  'techo', 'teclado', 'tejado', 'tejo', 'templo', 'tenedor', 'termita', 'ternera',
  'tienda', 'tierra', 'tigre', 'tijera', 'timbre', 'toalla', 'tobillo', 'tomillo',
  'topo', 'tordo', 'tormenta', 'tornillo', 'toro', 'torre', 'tortilla', 'trigo',
  'tronco', 'trucha', 'trueno', 'tubo', 'tuerca', 'tundra', 'turquesa', 'urraca',
  'uva', 'vaca', 'vado', 'vainilla', 'valla', 'vaso', 'vela', 'vena',
];
