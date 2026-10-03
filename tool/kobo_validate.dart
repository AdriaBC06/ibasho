// Kōbō — validador CLI de paquetes .ibasho.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

// Importa únicamente el núcleo Dart puro. No usar extensions.dart aquí:
// ese barrel también exporta AddonManager, que depende de path_provider/Flutter.
import 'package:ibasho/extensions/verification.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Uso: dart run tool/kobo_validate.dart <paquete.ibasho>');
    exitCode = 64;
    return;
  }

  final file = File(args.single);
  if (!await file.exists()) {
    stderr.writeln('No existe: ${file.path}');
    exitCode = 66;
    return;
  }

  try {
    final verified = await const PackageVerifier().verify(file);
    stdout.writeln('OK ${verified.manifest.id}@${verified.manifest.version}');
    stdout.writeln('tipo: ${verified.manifest.type.wireName}');
    stdout.writeln('publisher: ${verified.manifest.publisher}');
    stdout.writeln('sha256: ${verified.sha256}');
    stdout.writeln('entradas: ${verified.entryCount}');
    stdout.writeln('comprimido: ${verified.compressedBytes} bytes');
    stdout.writeln(
      'descomprimido declarado: ${verified.uncompressedBytes} bytes',
    );
  } on ExtensionException catch (error) {
    stderr.writeln(error);
    exitCode = 65;
  }
}
