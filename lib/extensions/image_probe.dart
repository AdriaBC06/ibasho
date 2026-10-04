// Ibasho — lectura mínima y no renderizante de dimensiones raster.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'extension_error.dart';

class RasterDimensions {
  const RasterDimensions(this.width, this.height);

  final int width;
  final int height;
}

RasterDimensions probeRasterDimensions(List<int> bytes, String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return _png(bytes, path);
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
    return _jpeg(bytes, path);
  if (lower.endsWith('.webp')) return _webp(bytes, path);
  throw ExtensionException(
    ExtensionErrorCode.invalidPackage,
    'Formato raster no permitido para icon/preview. Use PNG, JPEG o WebP.',
    subject: path,
  );
}

RasterDimensions _png(List<int> b, String path) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (b.length < 24) return _badImage(path);
  for (var i = 0; i < signature.length; i++) {
    if (b[i] != signature[i]) return _badImage(path);
  }
  if (String.fromCharCodes(b.sublist(12, 16)) != 'IHDR') return _badImage(path);
  final width = _be32(b, 16);
  final height = _be32(b, 20);
  return _checked(width, height, path);
}

RasterDimensions _jpeg(List<int> b, String path) {
  if (b.length < 4 || b[0] != 0xff || b[1] != 0xd8) return _badImage(path);
  var i = 2;
  while (i + 3 < b.length) {
    if (b[i] != 0xff) {
      i++;
      continue;
    }
    while (i < b.length && b[i] == 0xff) {
      i++;
    }
    if (i >= b.length) break;
    final marker = b[i++];
    if (marker == 0xd9 || marker == 0xda) break;
    if (marker == 0x01 || marker >= 0xd0 && marker <= 0xd7) continue;
    if (i + 1 >= b.length) break;
    final length = (b[i] << 8) | b[i + 1];
    if (length < 2 || i + length > b.length) return _badImage(path);
    if (_jpegSofMarkers.contains(marker)) {
      if (length < 7) return _badImage(path);
      final height = (b[i + 3] << 8) | b[i + 4];
      final width = (b[i + 5] << 8) | b[i + 6];
      return _checked(width, height, path);
    }
    i += length;
  }
  return _badImage(path);
}

const Set<int> _jpegSofMarkers = <int>{
  0xc0,
  0xc1,
  0xc2,
  0xc3,
  0xc5,
  0xc6,
  0xc7,
  0xc9,
  0xca,
  0xcb,
  0xcd,
  0xce,
  0xcf,
};

RasterDimensions _webp(List<int> b, String path) {
  if (b.length < 30 ||
      String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(b.sublist(8, 12)) != 'WEBP') {
    return _badImage(path);
  }
  final kind = String.fromCharCodes(b.sublist(12, 16));
  if (kind == 'VP8X') {
    final width = 1 + _le24(b, 24);
    final height = 1 + _le24(b, 27);
    return _checked(width, height, path);
  }
  if (kind == 'VP8L') {
    if (b[20] != 0x2f) return _badImage(path);
    final width = 1 + (b[21] | ((b[22] & 0x3f) << 8));
    final height = 1 + ((b[22] >> 6) | (b[23] << 2) | ((b[24] & 0x0f) << 10));
    return _checked(width, height, path);
  }
  if (kind == 'VP8 ') {
    if (b[23] != 0x9d || b[24] != 0x01 || b[25] != 0x2a) return _badImage(path);
    final width = (b[26] | (b[27] << 8)) & 0x3fff;
    final height = (b[28] | (b[29] << 8)) & 0x3fff;
    return _checked(width, height, path);
  }
  return _badImage(path);
}

RasterDimensions _checked(int width, int height, String path) {
  if (width <= 0 || height <= 0) return _badImage(path);
  return RasterDimensions(width, height);
}

Never _badImage(String path) {
  throw ExtensionException(
    ExtensionErrorCode.invalidPackage,
    'Imagen raster inválida o no reconocida.',
    subject: path,
  );
}

int _be32(List<int> b, int offset) =>
    (b[offset] << 24) |
    (b[offset + 1] << 16) |
    (b[offset + 2] << 8) |
    b[offset + 3];

int _le24(List<int> b, int offset) =>
    b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16);
