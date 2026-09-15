// Ibasho — guardado cifrado de la sesion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// Almacen de secretos. El token de refresco nunca toca el disco en claro.
abstract interface class SecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Nombre de la implementacion activa, para la pantalla de creditos y los
  /// registros de arranque.
  String get backendName;
}

/// Elige el almacen: llavero del sistema si responde, cifrado propio si no.
///
/// En Linux `flutter_secure_storage` habla con libsecret, que necesita un
/// servicio de secretos en marcha (gnome-keyring, kwallet…). Cuando no lo hay
/// la escritura falla, asi que se comprueba con una clave de sonda antes de
/// confiar en el.
Future<SecureStore> openSecureStore() async {
  const probeKey = 'ibasho.probe';
  try {
    const keyring = FlutterSecureStorage(lOptions: LinuxOptions());
    await keyring.write(key: probeKey, value: 'ok');
    final back = await keyring.read(key: probeKey);
    await keyring.delete(key: probeKey);
    if (back == 'ok') return _KeyringStore(keyring);
  } catch (e) {
    debugPrint('Ibasho: no hay llavero del sistema ($e), se usa cifrado propio');
  }
  return _EncryptedFileStore(await _vaultFile());
}

Future<File> _vaultFile() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File('${dir.path}/session.vault');
}

class _KeyringStore implements SecureStore {
  const _KeyringStore(this._storage);

  final FlutterSecureStorage _storage;

  @override
  String get backendName => 'libsecret';

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Respaldo: un unico archivo cifrado con AES-256-GCM.
///
/// La clave sale de PBKDF2 sobre el identificador de la maquina, la ruta del
/// almacen y una sal aleatoria por instalacion. No es un llavero de verdad
/// —quien tenga el disco y la maquina puede descifrarlo— pero cumple lo que
/// pide el checkpoint: ningun token en texto plano.
class _EncryptedFileStore implements SecureStore {
  _EncryptedFileStore(this._file);

  final File _file;

  static const int _iterations = 120000;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macBits = 128;

  Uint8List? _key;
  Map<String, String>? _cache;

  @override
  String get backendName => 'aes-256-gcm';

  File get _saltFile => File('${_file.path}.salt');

  Future<Uint8List> _deriveKey() async {
    if (_key != null) return _key!;

    Uint8List salt;
    if (await _saltFile.exists()) {
      salt = Uint8List.fromList(await _saltFile.readAsBytes());
    } else {
      final random = Random.secure();
      salt = Uint8List.fromList(
        List<int>.generate(_saltLength, (_) => random.nextInt(256)),
      );
      await _saltFile.writeAsBytes(salt, flush: true);
    }

    final material = <String>[
      'ibasho.session.v1',
      await _machineId(),
      _file.path,
    ].join('|');

    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, 32));
    return _key = kdf.process(Uint8List.fromList(utf8.encode(material)));
  }

  static Future<String> _machineId() async {
    for (final path in const ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
      final file = File(path);
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        if (value.isNotEmpty) return value;
      }
    }
    return '${Platform.localHostname}|${Platform.environment['HOME'] ?? ''}';
  }

  GCMBlockCipher _cipher(Uint8List key, Uint8List nonce, {required bool encrypt}) =>
      GCMBlockCipher(AESEngine())
        ..init(encrypt,
            AEADParameters(KeyParameter(key), _macBits, nonce, Uint8List(0)));

  Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;
    if (!await _file.exists()) return _cache = <String, String>{};
    try {
      final raw = await _file.readAsBytes();
      if (raw.length <= _nonceLength) return _cache = <String, String>{};
      final nonce = Uint8List.sublistView(raw, 0, _nonceLength);
      final body = Uint8List.sublistView(raw, _nonceLength);
      final plain = _cipher(await _deriveKey(), nonce, encrypt: false).process(body);
      final decoded = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
      return _cache = decoded.map((k, v) => MapEntry(k, '$v'));
    } catch (e) {
      // Archivo de otra maquina, corrupto o con la sal cambiada: se descarta.
      debugPrint('Ibasho: el almacen cifrado no se ha podido abrir ($e)');
      return _cache = <String, String>{};
    }
  }

  Future<void> _save() async {
    final random = Random.secure();
    final nonce = Uint8List.fromList(
      List<int>.generate(_nonceLength, (_) => random.nextInt(256)),
    );
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(_cache ?? const {})));
    final body = _cipher(await _deriveKey(), nonce, encrypt: true).process(plain);
    await _file.writeAsBytes(
      Uint8List.fromList(<int>[...nonce, ...body]),
      flush: true,
    );
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String value) async {
    (await _load())[key] = value;
    await _save();
  }

  @override
  Future<void> delete(String key) async {
    (await _load()).remove(key);
    await _save();
  }
}
