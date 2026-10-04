// Ibasho — verificación y extracción segura de paquetes .ibasho.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'extension_error.dart';
import 'image_probe.dart';
import 'manifest.dart';
import 'path_policy.dart';

class PackageLimits {
  const PackageLimits({
    this.maxCompressedBytes = 50 * 1024 * 1024,
    this.maxUncompressedBytes = 150 * 1024 * 1024,
    this.maxEntries = 500,
    this.maxManifestBytes = 64 * 1024,
    this.maxIconBytes = 2 * 1024 * 1024,
    this.maxPreviewBytes = 4 * 1024 * 1024,
    this.maxRasterDimension = 4096,
    this.maxCompressionRatio = 100,
  });

  final int maxCompressedBytes;
  final int maxUncompressedBytes;
  final int maxEntries;
  final int maxManifestBytes;
  final int maxIconBytes;
  final int maxPreviewBytes;
  final int maxRasterDimension;
  final int maxCompressionRatio;
}

class VerifiedPackage {
  const VerifiedPackage({
    required this.manifest,
    required this.sha256,
    required this.compressedBytes,
    required this.uncompressedBytes,
    required this.entryCount,
    required this.files,
  });

  final ExtensionManifest manifest;
  final String sha256;
  final int compressedBytes;
  final int uncompressedBytes;
  final int entryCount;
  final Map<String, int> files;
}

class PackageVerifier {
  const PackageVerifier({
    this.limits = const PackageLimits(),
    this.parser = const ManifestParser(),
  });

  final PackageLimits limits;
  final ManifestParser parser;

  Future<VerifiedPackage> verify(File package) async {
    final compressedBytes = await package.length();
    if (compressedBytes <= 0 || compressedBytes > limits.maxCompressedBytes) {
      throw ExtensionException(
        ExtensionErrorCode.sizeLimitExceeded,
        'El paquete supera el límite comprimido de ${limits.maxCompressedBytes} bytes.',
        subject: package.path,
      );
    }

    final digest = await sha256.bind(package.openRead()).first;
    final input = InputFileStream(package.path);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input);
      final files = <String, int>{};
      final entryKinds = <String, bool>{};
      final collisionKeys = <String>{};
      ArchiveFile? manifestEntry;
      var uncompressedBytes = 0;
      var count = 0;

      for (final entry in archive) {
        count++;
        if (count > limits.maxEntries) {
          throw ExtensionException(
            ExtensionErrorCode.tooManyEntries,
            'El paquete contiene más de ${limits.maxEntries} entradas.',
            subject: entry.name,
          );
        }
        if (entry.isSymbolicLink) {
          throw ExtensionException(
            ExtensionErrorCode.unsupportedEntry,
            'No se permiten enlaces simbólicos.',
            subject: entry.name,
          );
        }
        _rejectSpecialFile(entry);

        final normalized = validatePackagePath(
          entry.name,
          subject: entry.name,
          allowTrailingSlash: true,
        );
        final collisionKey = normalized.toLowerCase();
        if (!collisionKeys.add(collisionKey)) {
          throw ExtensionException(
            ExtensionErrorCode.duplicateEntry,
            'Dos entradas colisionan después de normalización portable.',
            subject: normalized,
          );
        }

        if (entry.isFile) {
          if (hasForbiddenExecutableExtension(normalized)) {
            throw ExtensionException(
              ExtensionErrorCode.unsupportedEntry,
              'IES 0.1 no admite código ejecutable dentro de un paquete.',
              subject: normalized,
            );
          }
          if (entry.size < 0) {
            throw ExtensionException(
              ExtensionErrorCode.invalidPackage,
              'Entrada con tamaño inválido.',
              subject: normalized,
            );
          }
          uncompressedBytes += entry.size;
          if (uncompressedBytes > limits.maxUncompressedBytes) {
            throw ExtensionException(
              ExtensionErrorCode.sizeLimitExceeded,
              'El paquete supera el límite descomprimido de ${limits.maxUncompressedBytes} bytes.',
              subject: package.path,
            );
          }
          files[normalized] = entry.size;
          entryKinds[normalized] = true;
          if (normalized == 'manifest.json') {
            manifestEntry = entry;
          }
        } else if (entry.isDirectory) {
          entryKinds[normalized] = false;
        } else {
          throw ExtensionException(
            ExtensionErrorCode.unsupportedEntry,
            'Tipo de entrada ZIP no soportado.',
            subject: normalized,
          );
        }
      }

      if (compressedBytes > 0 &&
          uncompressedBytes > compressedBytes * limits.maxCompressionRatio) {
        throw ExtensionException(
          ExtensionErrorCode.sizeLimitExceeded,
          'El ratio de compresión del paquete excede ${limits.maxCompressionRatio}:1.',
          subject: package.path,
        );
      }

      if (manifestEntry == null) {
        throw const ExtensionException(
          ExtensionErrorCode.invalidPackage,
          'Falta manifest.json en la raíz del paquete.',
          subject: 'manifest.json',
        );
      }
      if (manifestEntry.size > limits.maxManifestBytes) {
        throw ExtensionException(
          ExtensionErrorCode.sizeLimitExceeded,
          'manifest.json supera ${limits.maxManifestBytes} bytes.',
          subject: 'manifest.json',
        );
      }
      final manifestBytes = _readEntryLimited(
        manifestEntry,
        limits.maxManifestBytes,
        subject: 'manifest.json',
      );
      final manifest = parser.parseBytes(manifestBytes);
      _validateReferences(manifest, files, entryKinds, archive);

      return VerifiedPackage(
        manifest: manifest,
        sha256: digest.toString(),
        compressedBytes: compressedBytes,
        uncompressedBytes: uncompressedBytes,
        entryCount: count,
        files: Map<String, int>.unmodifiable(files),
      );
    } on ExtensionException {
      rethrow;
    } catch (error) {
      throw ExtensionException(
        ExtensionErrorCode.invalidPackage,
        'ZIP inválido o corrupto.',
        subject: package.path,
        cause: error,
      );
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  Future<void> extractVerified(
    File package,
    VerifiedPackage verified,
    Directory output,
  ) async {
    final digest = await sha256.bind(package.openRead()).first;
    if (digest.toString() != verified.sha256) {
      throw ExtensionException(
        ExtensionErrorCode.integrityMismatch,
        'El paquete cambió después de ser verificado.',
        subject: package.path,
      );
    }

    if (await output.exists()) {
      await output.delete(recursive: true);
    }
    await output.create(recursive: true);

    final input = InputFileStream(package.path);
    Archive? archive;
    try {
      archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        if (entry.isSymbolicLink) {
          throw ExtensionException(
            ExtensionErrorCode.integrityMismatch,
            'La segunda lectura contiene un symlink inesperado.',
            subject: entry.name,
          );
        }
        _rejectSpecialFile(entry);
        final normalized = validatePackagePath(
          entry.name,
          subject: entry.name,
          allowTrailingSlash: true,
        );
        final target = _targetPath(output.path, normalized);
        if (entry.isDirectory) {
          await Directory(target).create(recursive: true);
          continue;
        }
        if (!entry.isFile || !verified.files.containsKey(normalized)) {
          throw ExtensionException(
            ExtensionErrorCode.integrityMismatch,
            'La estructura del ZIP cambió después de verificarse.',
            subject: normalized,
          );
        }
        await Directory(p.dirname(target)).create(recursive: true);
        final expected = verified.files[normalized]!;
        final content = entry.getContent();
        if (content == null && expected != 0) {
          throw ExtensionException(
            ExtensionErrorCode.invalidPackage,
            'No se pudo abrir el contenido de la entrada.',
            subject: normalized,
          );
        }
        final sink = File(target).openWrite();
        var actual = 0;
        try {
          if (content != null) {
            while (!content.isEOS) {
              final remaining = content.length;
              if (remaining <= 0) break;
              final count = remaining > 64 * 1024 ? 64 * 1024 : remaining;
              final chunk = content.readBytes(count).toUint8List();
              actual += chunk.length;
              if (actual > expected || actual > limits.maxUncompressedBytes) {
                throw ExtensionException(
                  ExtensionErrorCode.sizeLimitExceeded,
                  'La entrada produce más datos que los declarados.',
                  subject: normalized,
                );
              }
              sink.add(chunk);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
          content?.closeSync();
        }
        if (actual != expected) {
          throw ExtensionException(
            ExtensionErrorCode.integrityMismatch,
            'El tamaño extraído no coincide con el verificado.',
            subject: normalized,
          );
        }
      }
    } on ExtensionException {
      if (await output.exists()) {
        await output.delete(recursive: true);
      }
      rethrow;
    } catch (error) {
      if (await output.exists()) {
        await output.delete(recursive: true);
      }
      throw ExtensionException(
        ExtensionErrorCode.invalidPackage,
        'ZIP inválido durante la extracción.',
        subject: package.path,
        cause: error,
      );
    } finally {
      archive?.clearSync();
      input.closeSync();
    }
  }

  void _validateReferences(
    ExtensionManifest manifest,
    Map<String, int> files,
    Map<String, bool> entryKinds,
    Archive archive,
  ) {
    _requireFile(manifest.assets.icon, files, 'assets.icon');
    _validateRaster(
      manifest.assets.icon,
      files,
      archive,
      maxBytes: limits.maxIconBytes,
    );

    final preview = manifest.assets.preview;
    if (preview != null) {
      _requireFile(preview, files, 'assets.preview');
      _validateRaster(
        preview,
        files,
        archive,
        maxBytes: limits.maxPreviewBytes,
      );
    }

    for (final item in manifest.locales.entries) {
      _requireFile(item.value, files, 'locales.${item.key}');
    }

    final content = manifest.entry.content;
    if (content != null) {
      final direct = entryKinds.containsKey(content);
      final prefix = '$content/';
      final hasChildren = entryKinds.keys.any(
        (path) => path.startsWith(prefix),
      );
      if (!direct && !hasChildren) {
        throw ExtensionException(
          ExtensionErrorCode.invalidPackage,
          'entry.content no existe en el paquete.',
          subject: content,
        );
      }
    }
  }

  void _validateRaster(
    String path,
    Map<String, int> files,
    Archive archive, {
    required int maxBytes,
  }) {
    final size = files[path]!;
    if (size > maxBytes) {
      throw ExtensionException(
        ExtensionErrorCode.sizeLimitExceeded,
        'El raster supera el límite de $maxBytes bytes.',
        subject: path,
      );
    }
    final entry = archive.firstWhere((item) {
      final name = validatePackagePath(
        item.name,
        subject: item.name,
        allowTrailingSlash: true,
      );
      return item.isFile && name == path;
    });
    final bytes = _readEntryLimited(entry, maxBytes, subject: path);
    final dimensions = probeRasterDimensions(bytes, path);
    if (dimensions.width > limits.maxRasterDimension ||
        dimensions.height > limits.maxRasterDimension) {
      throw ExtensionException(
        ExtensionErrorCode.sizeLimitExceeded,
        'La imagen excede ${limits.maxRasterDimension}×${limits.maxRasterDimension}px.',
        subject: path,
      );
    }
  }

  static void _requireFile(
    String path,
    Map<String, int> files,
    String subject,
  ) {
    if (!files.containsKey(path)) {
      throw ExtensionException(
        ExtensionErrorCode.invalidPackage,
        'La ruta declarada no existe como archivo: $path',
        subject: subject,
      );
    }
  }

  static List<int> _readEntryLimited(
    ArchiveFile entry,
    int maxBytes, {
    required String subject,
  }) {
    final content = entry.getContent();
    if (content == null) {
      if (entry.size == 0) return const <int>[];
      throw ExtensionException(
        ExtensionErrorCode.invalidPackage,
        'No se pudo abrir el contenido de la entrada.',
        subject: subject,
      );
    }
    final bytes = <int>[];
    try {
      while (!content.isEOS) {
        final remaining = content.length;
        if (remaining <= 0) break;
        final count = remaining > 64 * 1024 ? 64 * 1024 : remaining;
        final chunk = content.readBytes(count).toUint8List();
        if (bytes.length + chunk.length > maxBytes) {
          throw ExtensionException(
            ExtensionErrorCode.sizeLimitExceeded,
            'La entrada supera el límite de $maxBytes bytes al descomprimir.',
            subject: subject,
          );
        }
        bytes.addAll(chunk);
      }
    } finally {
      content.closeSync();
    }
    if (bytes.length != entry.size) {
      throw ExtensionException(
        ExtensionErrorCode.integrityMismatch,
        'El tamaño real de la entrada no coincide con el declarado.',
        subject: subject,
      );
    }
    return bytes;
  }

  static void _rejectSpecialFile(ArchiveFile entry) {
    if (entry.isSymbolicLink) return;
    // POSIX S_IFMT. Algunos ZIP no guardan tipo y dejan estos bits en cero.
    final kind = entry.mode & 0xf000;
    const regular = 0x8000;
    const directory = 0x4000;
    if (kind != 0 && kind != regular && kind != directory) {
      throw ExtensionException(
        ExtensionErrorCode.unsupportedEntry,
        'No se permiten archivos especiales.',
        subject: entry.name,
      );
    }
  }

  static String _targetPath(String root, String portablePath) {
    final parts = portablePath.split('/');
    final target = p.normalize(p.joinAll(<String>[root, ...parts]));
    final rootNormalized = p.normalize(p.absolute(root));
    final targetNormalized = p.normalize(p.absolute(target));
    if (!p.isWithin(rootNormalized, targetNormalized) &&
        targetNormalized != rootNormalized) {
      throw ExtensionException(
        ExtensionErrorCode.unsafePath,
        'La ruta escapa del staging.',
        subject: portablePath,
      );
    }
    return target;
  }
}
