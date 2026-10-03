// Ibasho — instalación transaccional y registro local de extensiones.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/version.dart';
import 'extension_error.dart';
import 'install_policy.dart';
import 'manifest.dart';
import 'package_verifier.dart';
import 'semver.dart';

enum ExtensionTrust {
  localUnsigned('local-unsigned');

  const ExtensionTrust(this.wireName);
  final String wireName;
}

class InstalledExtension {
  const InstalledExtension({
    required this.manifest,
    required this.enabled,
    required this.trust,
    required this.packageSha256,
    required this.installedAt,
    required this.installDirectory,
  });

  final ExtensionManifest manifest;
  final bool enabled;
  final ExtensionTrust trust;
  final String packageSha256;
  final DateTime installedAt;
  final Directory installDirectory;
}

class InstalledExtensionVersion {
  const InstalledExtensionVersion({
    required this.manifest,
    required this.trust,
    required this.packageSha256,
    required this.installedAt,
    required this.installDirectory,
    required this.active,
  });

  final ExtensionManifest manifest;
  final ExtensionTrust trust;
  final String packageSha256;
  final DateTime installedAt;
  final Directory installDirectory;
  final bool active;
}

class AddonManager {
  AddonManager._({
    required this.root,
    required this.verifier,
    required this.host,
    required this.policy,
  });

  final Directory root;
  final PackageVerifier verifier;
  final ExtensionHostProfile host;
  final ExtensionInstallPolicy policy;

  Future<void> _mutationTail = Future<void>.value();

  Directory get _packages => Directory(p.join(root.path, 'packages'));
  Directory get _staging => Directory(p.join(root.path, '.staging'));
  File get _index => File(p.join(root.path, 'installed-v1.json'));
  File get _indexBackup => File(p.join(root.path, 'installed-v1.json.bak'));

  static Future<AddonManager> open({
    Directory? root,
    PackageVerifier verifier = const PackageVerifier(),
    ExtensionHostProfile? host,
    ExtensionInstallPolicy policy = const ExtensionInstallPolicy(),
  }) async {
    final support =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'extensions'),
        );
    final manager = AddonManager._(
      root: support,
      verifier: verifier,
      host:
          host ??
          ExtensionHostProfile(ibashoVersion: SemVersion.parse(appVersion)),
      policy: policy,
    );
    await manager._prepare();
    return manager;
  }

  Future<void> _prepare() async {
    await root.create(recursive: true);
    await _packages.create(recursive: true);
    if (await _staging.exists()) {
      await _staging.delete(recursive: true);
    }
    await _staging.create(recursive: true);
    final pending = File('${_index.path}.new');
    if (!await _index.exists() && await _indexBackup.exists()) {
      await _indexBackup.rename(_index.path);
    }
    if (await pending.exists()) {
      await pending.delete();
    }
    if (!await _index.exists()) {
      await _writeIndex(_emptyIndex());
    } else {
      await _readIndex();
    }
  }

  Future<InstalledExtension> install(
    File source, {
    bool enable = true,
  }) => _serialized(() async {
    final transaction = Directory(
      p.join(_staging.path, _randomTransactionId()),
    );
    await transaction.create(recursive: true);
    final copied = File(p.join(transaction.path, 'package.ibasho'));
    try {
      await _copyWithLimit(source, copied, verifier.limits.maxCompressedBytes);
      final verified = await verifier.verify(copied);
      policy.validate(verified.manifest);
      host.requireCompatible(verified.manifest);

      final index = await _readIndex();
      final existing = _entryFor(index, verified.manifest.id);
      if (existing != null) {
        final active = SemVersion.parse(existing.activeVersion);
        if (!policy.allowDowngrade && verified.manifest.version < active) {
          throw ExtensionException(
            ExtensionErrorCode.downgradeBlocked,
            'Downgrade bloqueado: activa $active, paquete ${verified.manifest.version}.',
            subject: verified.manifest.id,
          );
        }
      }

      final finalDirectory = Directory(
        p.join(
          _packages.path,
          verified.manifest.id,
          verified.manifest.version.toString(),
        ),
      );
      if (await finalDirectory.exists()) {
        throw ExtensionException(
          ExtensionErrorCode.alreadyInstalled,
          'Esta versión ya está instalada.',
          subject: '${verified.manifest.id}@${verified.manifest.version}',
        );
      }

      final now = DateTime.now().toUtc();
      final payload = Directory(p.join(transaction.path, 'payload'));
      await verifier.extractVerified(copied, verified, payload);
      await _writeInstallMetadata(payload, verified, now);
      await finalDirectory.parent.create(recursive: true);
      await payload.rename(finalDirectory.path);
      final previousRaw = index.extensions[verified.manifest.id];
      index.extensions[verified.manifest.id] = _IndexEntry(
        activeVersion: verified.manifest.version.toString(),
        enabled: enable,
        trust: ExtensionTrust.localUnsigned.wireName,
        packageSha256: verified.sha256,
        installedAt: now.toIso8601String(),
      );
      try {
        await _writeIndex(index);
      } catch (_) {
        if (previousRaw == null) {
          index.extensions.remove(verified.manifest.id);
        } else {
          index.extensions[verified.manifest.id] = previousRaw;
        }
        if (await finalDirectory.exists()) {
          await finalDirectory.delete(recursive: true);
        }
        rethrow;
      }

      return InstalledExtension(
        manifest: verified.manifest,
        enabled: enable,
        trust: ExtensionTrust.localUnsigned,
        packageSha256: verified.sha256,
        installedAt: now,
        installDirectory: finalDirectory,
      );
    } finally {
      if (await transaction.exists()) {
        await transaction.delete(recursive: true);
      }
    }
  });

  Future<List<InstalledExtension>> listInstalled() async {
    final index = await _readIndex();
    final result = <InstalledExtension>[];
    for (final item in index.extensions.entries) {
      final id = item.key;
      final record = item.value;
      final directory = Directory(
        p.join(_packages.path, id, record.activeVersion),
      );
      final manifestFile = File(p.join(directory.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw ExtensionException(
          ExtensionErrorCode.corruptIndex,
          'El índice apunta a una instalación inexistente.',
          subject: '$id@${record.activeVersion}',
        );
      }
      final manifest = verifier.parser.parseBytes(
        await manifestFile.readAsBytes(),
      );
      if (manifest.id != id ||
          manifest.version.toString() != record.activeVersion) {
        throw ExtensionException(
          ExtensionErrorCode.corruptIndex,
          'El manifiesto instalado no coincide con el índice.',
          subject: '$id@${record.activeVersion}',
        );
      }
      result.add(
        InstalledExtension(
          manifest: manifest,
          enabled: record.enabled,
          trust: _parseTrust(record.trust),
          packageSha256: record.packageSha256,
          installedAt: DateTime.parse(record.installedAt).toUtc(),
          installDirectory: directory,
        ),
      );
    }
    result.sort((a, b) => a.manifest.id.compareTo(b.manifest.id));
    return result;
  }

  Future<List<InstalledExtensionVersion>> listInstalledVersions(
    String id,
  ) async {
    final index = await _readIndex();
    final current = _entryFor(index, id);
    if (current == null) {
      return const <InstalledExtensionVersion>[];
    }

    final base = Directory(p.join(_packages.path, id));
    if (!await base.exists()) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'El índice apunta a una extensión sin directorio de versiones.',
        subject: id,
      );
    }

    final result = <InstalledExtensionVersion>[];
    await for (final entity in base.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final versionName = p.basename(entity.path);
      final parsed = SemVersion.tryParse(versionName);
      if (parsed == null) continue;

      final manifestFile = File(p.join(entity.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw ExtensionException(
          ExtensionErrorCode.corruptIndex,
          'Una versión instalada no contiene manifest.json.',
          subject: '$id@$versionName',
        );
      }

      final manifest = verifier.parser.parseBytes(
        await manifestFile.readAsBytes(),
      );
      if (manifest.id != id || manifest.version != parsed) {
        throw ExtensionException(
          ExtensionErrorCode.corruptIndex,
          'El manifiesto de una versión instalada no coincide con su ruta.',
          subject: '$id@$versionName',
        );
      }

      policy.validate(manifest);
      host.requireCompatible(manifest);
      final metadata = await _readInstallMetadata(entity);
      result.add(
        InstalledExtensionVersion(
          manifest: manifest,
          trust: _parseTrust(metadata.trust),
          packageSha256: metadata.packageSha256,
          installedAt: DateTime.parse(metadata.installedAt).toUtc(),
          installDirectory: entity,
          active: versionName == current.activeVersion,
        ),
      );
    }

    result.sort((a, b) => b.manifest.version.compareTo(a.manifest.version));
    return result;
  }

  Future<void> setEnabled(String id, bool enabled) => _serialized(() async {
    final index = await _readIndex();
    final record = _entryFor(index, id);
    if (record == null) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Extensión no instalada.',
        subject: id,
      );
    }
    index.extensions[id] = record.copyWith(enabled: enabled);
    await _writeIndex(index);
  });

  Future<void> activateVersion(String id, String version) =>
      _serialized(() async {
        final parsed = SemVersion.parse(version, subject: id);
        final directory = Directory(
          p.join(_packages.path, id, parsed.toString()),
        );
        final manifestFile = File(p.join(directory.path, 'manifest.json'));
        if (!await manifestFile.exists()) {
          throw ExtensionException(
            ExtensionErrorCode.corruptIndex,
            'La versión solicitada no está instalada.',
            subject: '$id@$version',
          );
        }
        final manifest = verifier.parser.parseBytes(
          await manifestFile.readAsBytes(),
        );
        if (manifest.id != id || manifest.version != parsed) {
          throw ExtensionException(
            ExtensionErrorCode.corruptIndex,
            'El manifiesto de la versión no coincide.',
            subject: '$id@$version',
          );
        }
        policy.validate(manifest);
        host.requireCompatible(manifest);
        final index = await _readIndex();
        final current = _entryFor(index, id);
        if (current == null) {
          throw ExtensionException(
            ExtensionErrorCode.corruptIndex,
            'La extensión no figura en el índice.',
            subject: id,
          );
        }
        final installMetadata = await _readInstallMetadata(directory);
        index.extensions[id] = _IndexEntry(
          activeVersion: parsed.toString(),
          enabled: current.enabled,
          trust: installMetadata.trust,
          packageSha256: installMetadata.packageSha256,
          installedAt: installMetadata.installedAt,
        );
        await _writeIndex(index);
      });

  Future<void> uninstall(String id, {bool deleteAllVersions = true}) =>
      _serialized(() async {
        final index = await _readIndex();
        if (!index.extensions.containsKey(id)) return;
        final previous = index.extensions.remove(id)!;
        await _writeIndex(index);
        if (deleteAllVersions) {
          final directory = Directory(p.join(_packages.path, id));
          try {
            if (await directory.exists()) {
              await directory.delete(recursive: true);
            }
          } catch (error) {
            index.extensions[id] = previous;
            await _writeIndex(index);
            throw ExtensionException(
              ExtensionErrorCode.ioFailure,
              'No se pudo retirar la instalación del disco.',
              subject: id,
              cause: error,
            );
          }
        }
      });

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    return () async {
      try {
        await previous.catchError((Object _) {});
        return await action();
      } finally {
        release.complete();
      }
    }();
  }

  Future<_InstalledIndex> _readIndex() async {
    try {
      return await _decodeIndex(_index);
    } catch (error) {
      if (await _indexBackup.exists()) {
        try {
          final recovered = await _decodeIndex(_indexBackup);
          await _atomicReplace(_index, jsonEncode(recovered.toJson()));
          return recovered;
        } catch (_) {
          // El error original describe mejor el fallo principal.
        }
      }
      if (error is ExtensionException) rethrow;
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'No se pudo leer el índice de extensiones.',
        subject: _index.path,
        cause: error,
      );
    }
  }

  Future<_InstalledIndex> _decodeIndex(File file) async {
    final decodedRaw = jsonDecode(await file.readAsString());
    if (decodedRaw is! Map<dynamic, dynamic>) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Formato de índice inválido.',
        subject: file.path,
      );
    }
    final decoded = Map<String, Object?>.from(decodedRaw);
    if (decoded['format'] != 1) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Formato de índice inválido.',
        subject: file.path,
      );
    }
    final rawExtensions = decoded['extensions'];
    if (rawExtensions is! Map<dynamic, dynamic>) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'El índice no contiene extensions.',
        subject: file.path,
      );
    }
    final entries = <String, _IndexEntry>{};
    final extensionsMap = Map<String, Object?>.from(rawExtensions);
    for (final item in extensionsMap.entries) {
      if (item.value is! Map<dynamic, dynamic>) {
        throw ExtensionException(
          ExtensionErrorCode.corruptIndex,
          'Entrada inválida en el índice.',
          subject: item.key,
        );
      }
      entries[item.key] = _IndexEntry.fromJson(
        Map<String, Object?>.from(item.value! as Map<dynamic, dynamic>),
      );
    }
    return _InstalledIndex(entries);
  }

  Future<void> _writeIndex(_InstalledIndex value) async {
    await _atomicReplace(
      _index,
      const JsonEncoder.withIndent('  ').convert(value.toJson()),
    );
  }

  Future<void> _atomicReplace(File target, String text) async {
    final next = File('${target.path}.new');
    await next.writeAsString(text, flush: true);
    var backedUp = false;
    try {
      if (await target.exists()) {
        if (await _indexBackup.exists()) {
          await _indexBackup.delete();
        }
        await target.rename(_indexBackup.path);
        backedUp = true;
      }
      await next.rename(target.path);
    } catch (error) {
      if (await next.exists()) await next.delete();
      if (backedUp && !await target.exists() && await _indexBackup.exists()) {
        await _indexBackup.rename(target.path);
      }
      throw ExtensionException(
        ExtensionErrorCode.ioFailure,
        'No se pudo reemplazar el índice de forma segura.',
        subject: target.path,
        cause: error,
      );
    }
  }

  Future<void> _writeInstallMetadata(
    Directory payload,
    VerifiedPackage verified,
    DateTime installedAt,
  ) async {
    final file = File(p.join(payload.path, '.ibasho-install.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'format': 1,
        'trust': ExtensionTrust.localUnsigned.wireName,
        'packageSha256': verified.sha256,
        'verifiedCompressedBytes': verified.compressedBytes,
        'verifiedUncompressedBytes': verified.uncompressedBytes,
        'installedAt': installedAt.toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<_InstallMetadata> _readInstallMetadata(Directory directory) async {
    final file = File(p.join(directory.path, '.ibasho-install.json'));
    if (!await file.exists()) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Falta metadata de instalación.',
        subject: directory.path,
      );
    }
    final decodedRaw = jsonDecode(await file.readAsString());
    if (decodedRaw is! Map<dynamic, dynamic>) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Metadata de instalación inválida.',
        subject: file.path,
      );
    }
    final decoded = Map<String, Object?>.from(decodedRaw);
    if (decoded['format'] != 1) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Metadata de instalación inválida.',
        subject: file.path,
      );
    }
    final trust = decoded['trust'];
    final packageSha256 = decoded['packageSha256'];
    final installedAt = decoded['installedAt'];
    if (trust is! String ||
        packageSha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(packageSha256) ||
        installedAt is! String ||
        DateTime.tryParse(installedAt) == null) {
      throw ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Metadata de instalación incompleta.',
        subject: file.path,
      );
    }
    _parseTrust(trust);
    return _InstallMetadata(
      trust: trust,
      packageSha256: packageSha256,
      installedAt: installedAt,
    );
  }

  static Future<void> _copyWithLimit(
    File source,
    File destination,
    int maxBytes,
  ) async {
    var written = 0;
    IOSink? sink;
    try {
      sink = destination.openWrite();
      await for (final chunk in source.openRead()) {
        written += chunk.length;
        if (written > maxBytes) {
          throw ExtensionException(
            ExtensionErrorCode.sizeLimitExceeded,
            'El paquete supera el límite comprimido durante la copia.',
            subject: source.path,
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
    } on ExtensionException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ExtensionException(
        ExtensionErrorCode.ioFailure,
        'No se pudo copiar el paquete al staging.',
        subject: source.path,
        cause: error,
      );
    } finally {
      if (sink != null) await sink.close();
    }
  }

  static ExtensionTrust _parseTrust(String raw) {
    for (final value in ExtensionTrust.values) {
      if (value.wireName == raw) return value;
    }
    throw ExtensionException(
      ExtensionErrorCode.corruptIndex,
      'Estado de confianza desconocido: $raw',
    );
  }

  static _IndexEntry? _entryFor(_InstalledIndex index, String id) =>
      index.extensions[id];

  static _InstalledIndex _emptyIndex() =>
      _InstalledIndex(<String, _IndexEntry>{});

  static String _randomTransactionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _InstallMetadata {
  const _InstallMetadata({
    required this.trust,
    required this.packageSha256,
    required this.installedAt,
  });

  final String trust;
  final String packageSha256;
  final String installedAt;
}

class _InstalledIndex {
  _InstalledIndex(this.extensions);

  final Map<String, _IndexEntry> extensions;

  Map<String, Object?> toJson() => <String, Object?>{
    'format': 1,
    'extensions': <String, Object?>{
      for (final item in extensions.entries) item.key: item.value.toJson(),
    },
  };
}

class _IndexEntry {
  const _IndexEntry({
    required this.activeVersion,
    required this.enabled,
    required this.trust,
    required this.packageSha256,
    required this.installedAt,
  });

  final String activeVersion;
  final bool enabled;
  final String trust;
  final String packageSha256;
  final String installedAt;

  factory _IndexEntry.fromJson(Map<String, Object?> json) {
    final activeVersion = json['activeVersion'];
    final enabled = json['enabled'];
    final trust = json['trust'];
    final packageSha256 = json['packageSha256'];
    final installedAt = json['installedAt'];
    if (activeVersion is! String ||
        SemVersion.tryParse(activeVersion) == null ||
        enabled is! bool ||
        trust is! String ||
        packageSha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(packageSha256) ||
        installedAt is! String ||
        DateTime.tryParse(installedAt) == null) {
      throw const ExtensionException(
        ExtensionErrorCode.corruptIndex,
        'Entrada malformada en installed-v1.json.',
      );
    }
    return _IndexEntry(
      activeVersion: activeVersion,
      enabled: enabled,
      trust: trust,
      packageSha256: packageSha256,
      installedAt: installedAt,
    );
  }

  _IndexEntry copyWith({String? activeVersion, bool? enabled}) => _IndexEntry(
    activeVersion: activeVersion ?? this.activeVersion,
    enabled: enabled ?? this.enabled,
    trust: trust,
    packageSha256: packageSha256,
    installedAt: installedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'activeVersion': activeVersion,
    'enabled': enabled,
    'trust': trust,
    'packageSha256': packageSha256,
    'installedAt': installedAt,
  };
}
