// Ibasho — parser y modelo del manifiesto IES 1.x.
// Copyright (C) 2026 Julio Solano
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'extension_error.dart';
import 'path_policy.dart';
import 'semver.dart';

enum ExtensionType {
  contentPack('content-pack'),
  externalApp('external-app'),
  integratedApp('integrated-app');

  const ExtensionType(this.wireName);
  final String wireName;

  static ExtensionType? fromWireName(String value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    return null;
  }
}

abstract final class ExtensionCapabilities {
  static const Set<String> known = <String>{
    'theme.read',
    'locale.read',
    'profile.display_name.read',
    'tama.avatar.read',
    'storage.private.read',
    'storage.private.write',
    'game.report_started',
    'game.report_finished',
    'game.report_score',
  };

  static final RegExp _shape = RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$');
  static final RegExp _forbidden = RegExp(
    r'^(auth|firebase|crypto|messages|gacha|admin)(\.|$)|'
    r'^friends\.write$|^currency\.write$|^inventory\.write$',
  );

  static void validate(String capability, {required String subject}) {
    if (capability.length < 3 ||
        capability.length > 96 ||
        !_shape.hasMatch(capability)) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Capability con formato inválido: $capability',
        subject: subject,
      );
    }
    if (_forbidden.hasMatch(capability)) {
      throw ExtensionException(
        ExtensionErrorCode.forbiddenCapability,
        'Capability reservada o prohibida: $capability',
        subject: subject,
      );
    }
    if (!known.contains(capability)) {
      throw ExtensionException(
        ExtensionErrorCode.unknownCapability,
        'Capability desconocida por este host: $capability',
        subject: subject,
      );
    }
  }
}

class ExtensionCompatibility {
  const ExtensionCompatibility({
    required this.ibashoApi,
    required this.minimumIbasho,
    this.maximumIbasho,
  });

  final ApiRequirement ibashoApi;
  final SemVersion minimumIbasho;
  final SemVersion? maximumIbasho;

  Map<String, Object?> toJson() => <String, Object?>{
    'ibashoApi': ibashoApi.raw,
    'minIbasho': minimumIbasho.toString(),
    if (maximumIbasho != null) 'maxIbasho': maximumIbasho.toString(),
  };
}

class ExtensionEntry {
  const ExtensionEntry({
    this.url,
    this.content,
    this.allowedOrigins = const <String>[],
  });

  final Uri? url;
  final String? content;
  final List<String> allowedOrigins;

  Map<String, Object?> toJson() => <String, Object?>{
    if (url != null) 'url': url.toString(),
    if (content != null) 'content': content,
    if (allowedOrigins.isNotEmpty) 'allowedOrigins': allowedOrigins,
  };
}

class ExtensionAssets {
  const ExtensionAssets({required this.icon, this.preview});

  final String icon;
  final String? preview;

  Map<String, Object?> toJson() => <String, Object?>{
    'icon': icon,
    if (preview != null) 'preview': preview,
  };
}

class ExtensionManifest {
  const ExtensionManifest({
    required this.schema,
    required this.id,
    required this.name,
    required this.version,
    required this.publisher,
    required this.type,
    required this.compatibility,
    required this.entry,
    required this.permissions,
    required this.optionalPermissions,
    required this.assets,
    required this.locales,
    required this.metadata,
    this.description,
  });

  final int schema;
  final String id;
  final String name;
  final SemVersion version;
  final String publisher;
  final String? description;
  final ExtensionType type;
  final ExtensionCompatibility compatibility;
  final ExtensionEntry entry;
  final List<String> permissions;
  final List<String> optionalPermissions;
  final ExtensionAssets assets;
  final Map<String, String> locales;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': schema,
    'id': id,
    'name': name,
    'version': version.toString(),
    'publisher': publisher,
    if (description != null) 'description': description,
    'type': type.wireName,
    'compatibility': compatibility.toJson(),
    'entry': entry.toJson(),
    'permissions': permissions,
    if (optionalPermissions.isNotEmpty)
      'optionalPermissions': optionalPermissions,
    'assets': assets.toJson(),
    if (locales.isNotEmpty) 'locales': locales,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

class ManifestParser {
  const ManifestParser();

  static final RegExp _idPattern = RegExp(
    r'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$',
  );
  static final RegExp _localePattern = RegExp(r'^[a-z]{2}(?:-[A-Z]{2})?$');
  static final RegExp _originPattern = RegExp(
    r'^https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?$',
  );

  ExtensionManifest parseBytes(List<int> bytes) {
    late final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } on FormatException catch (error) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'manifest.json no es UTF-8 válido.',
        subject: 'manifest.json',
        cause: error,
      );
    }
    if (text.startsWith('\ufeff')) {
      throw const ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'manifest.json no debe incluir BOM.',
        subject: 'manifest.json',
      );
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'manifest.json contiene JSON inválido.',
        subject: 'manifest.json',
        cause: error,
      );
    }
    if (decoded is! Map<dynamic, dynamic>) {
      throw const ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'La raíz de manifest.json debe ser un objeto.',
        subject: 'manifest.json',
      );
    }
    return parseMap(Map<String, Object?>.from(decoded));
  }

  ExtensionManifest parseMap(Map<String, Object?> json) {
    final schema = _requiredInt(json, 'schema');
    if (schema != 1) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Schema no soportado: $schema.',
        subject: 'schema',
      );
    }

    final id = _requiredString(json, 'id', min: 3, max: 128);
    if (!_idPattern.hasMatch(id)) {
      throw const ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'ID inválido. Debe usar DNS inverso ASCII en minúsculas.',
        subject: 'id',
      );
    }

    final name = _requiredString(json, 'name', min: 1, max: 80);
    final version = SemVersion.parse(
      _requiredString(json, 'version'),
      subject: 'version',
    );
    final publisher = _requiredString(json, 'publisher', min: 1, max: 120);
    final description = _optionalString(json, 'description', max: 500);

    final typeRaw = _requiredString(json, 'type');
    final type = ExtensionType.fromWireName(typeRaw);
    if (type == null) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Tipo de extensión desconocido: $typeRaw',
        subject: 'type',
      );
    }

    final compatibilityMap = _requiredMap(json, 'compatibility');
    _rejectUnknown(compatibilityMap, const <String>{
      'ibashoApi',
      'minIbasho',
      'maxIbasho',
    }, 'compatibility');
    final requirement = ApiRequirement.parse(
      _requiredString(compatibilityMap, 'ibashoApi', min: 1, max: 32),
    );
    final minimumIbasho = SemVersion.parse(
      _requiredString(compatibilityMap, 'minIbasho'),
      subject: 'compatibility.minIbasho',
    );
    final maximumRaw = _optionalString(compatibilityMap, 'maxIbasho');
    final maximumIbasho = maximumRaw == null
        ? null
        : SemVersion.parse(maximumRaw, subject: 'compatibility.maxIbasho');
    if (maximumIbasho != null && maximumIbasho < minimumIbasho) {
      throw const ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'maxIbasho no puede ser menor que minIbasho.',
        subject: 'compatibility',
      );
    }

    final entryMap = _requiredMap(json, 'entry');
    ExtensionEntry entry;
    switch (type) {
      case ExtensionType.contentPack:
        _rejectUnknown(entryMap, const <String>{'content'}, 'entry');
        final content = validatePackagePath(
          _requiredString(entryMap, 'content', min: 1, max: 256),
          subject: 'entry.content',
        );
        entry = ExtensionEntry(content: content);
        break;
      case ExtensionType.externalApp:
      case ExtensionType.integratedApp:
        _rejectUnknown(entryMap, const <String>{
          'url',
          'allowedOrigins',
        }, 'entry');
        final url = _parseHttpsUrl(
          _requiredString(entryMap, 'url'),
          subject: 'entry.url',
        );
        final origins = _parseOrigins(entryMap['allowedOrigins']);
        if (type == ExtensionType.integratedApp && origins.isEmpty) {
          throw const ExtensionException(
            ExtensionErrorCode.invalidManifest,
            'Una integrated-app debe declarar al menos un allowedOrigin.',
            subject: 'entry.allowedOrigins',
          );
        }
        entry = ExtensionEntry(url: url, allowedOrigins: origins);
        break;
    }

    final permissions = _parseCapabilities(
      json['permissions'],
      subject: 'permissions',
      required: true,
    );
    final optionalPermissions = _parseCapabilities(
      json['optionalPermissions'],
      subject: 'optionalPermissions',
      required: false,
    );
    final overlap = permissions.toSet().intersection(
      optionalPermissions.toSet(),
    );
    if (overlap.isNotEmpty) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Una capability no puede ser obligatoria y opcional a la vez: ${overlap.join(', ')}',
        subject: 'permissions',
      );
    }

    final assetsMap = _requiredMap(json, 'assets');
    _rejectUnknown(assetsMap, const <String>{'icon', 'preview'}, 'assets');
    final icon = validatePackagePath(
      _requiredString(assetsMap, 'icon', min: 1, max: 256),
      subject: 'assets.icon',
    );
    final previewRaw = _optionalString(assetsMap, 'preview', max: 256);
    final preview = previewRaw == null
        ? null
        : validatePackagePath(previewRaw, subject: 'assets.preview');

    final locales = <String, String>{};
    final localesRaw = json['locales'];
    if (localesRaw != null) {
      if (localesRaw is! Map<dynamic, dynamic>) {
        throw const ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'locales debe ser un objeto.',
          subject: 'locales',
        );
      }
      final localeMap = Map<String, Object?>.from(localesRaw);
      for (final item in localeMap.entries) {
        if (!_localePattern.hasMatch(item.key)) {
          throw ExtensionException(
            ExtensionErrorCode.invalidManifest,
            'Locale inválido: ${item.key}',
            subject: 'locales',
          );
        }
        if (item.value is! String) {
          throw ExtensionException(
            ExtensionErrorCode.invalidManifest,
            'La ruta de ${item.key} debe ser texto.',
            subject: 'locales.${item.key}',
          );
        }
        locales[item.key] = validatePackagePath(
          item.value! as String,
          subject: 'locales.${item.key}',
        );
      }
    }

    final metadata = <String, Object?>{};
    final metadataRaw = json['metadata'];
    if (metadataRaw != null) {
      if (metadataRaw is! Map<dynamic, dynamic> || metadataRaw.length > 32) {
        throw const ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'metadata debe ser un objeto con un máximo de 32 propiedades.',
          subject: 'metadata',
        );
      }
      final metadataMap = Map<String, Object?>.from(metadataRaw);
      for (final item in metadataMap.entries) {
        final value = item.value;
        if (value != null &&
            value is! String &&
            value is! num &&
            value is! bool) {
          throw ExtensionException(
            ExtensionErrorCode.invalidManifest,
            'metadata.${item.key} debe ser un valor primitivo.',
            subject: 'metadata.${item.key}',
          );
        }
        metadata[item.key] = value;
      }
    }

    return ExtensionManifest(
      schema: schema,
      id: id,
      name: name,
      version: version,
      publisher: publisher,
      description: description,
      type: type,
      compatibility: ExtensionCompatibility(
        ibashoApi: requirement,
        minimumIbasho: minimumIbasho,
        maximumIbasho: maximumIbasho,
      ),
      entry: entry,
      permissions: permissions,
      optionalPermissions: optionalPermissions,
      assets: ExtensionAssets(icon: icon, preview: preview),
      locales: Map<String, String>.unmodifiable(locales),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  static List<String> _parseCapabilities(
    Object? raw, {
    required String subject,
    required bool required,
  }) {
    if (raw == null && !required) return const <String>[];
    if (raw is! List<Object?> || raw.length > 32) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$subject debe ser una lista con un máximo de 32 elementos.',
        subject: subject,
      );
    }
    final values = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Cada capability debe ser texto.',
          subject: subject,
        );
      }
      if (!seen.add(item)) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Capability duplicada: $item',
          subject: subject,
        );
      }
      ExtensionCapabilities.validate(item, subject: subject);
      values.add(item);
    }
    return List<String>.unmodifiable(values);
  }

  static List<String> _parseOrigins(Object? raw) {
    if (raw == null) return const <String>[];
    if (raw is! List<Object?> || raw.length > 8) {
      throw const ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'allowedOrigins debe ser una lista de máximo 8 elementos.',
        subject: 'entry.allowedOrigins',
      );
    }
    final values = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String || !_originPattern.hasMatch(item)) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Origin inválido: $item',
          subject: 'entry.allowedOrigins',
        );
      }
      final uri = Uri.tryParse(item);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.path.isNotEmpty ||
          uri.query.isNotEmpty ||
          uri.fragment.isNotEmpty ||
          uri.userInfo.isNotEmpty) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Origin HTTPS inválido: $item',
          subject: 'entry.allowedOrigins',
        );
      }
      if (!seen.add(item)) {
        throw ExtensionException(
          ExtensionErrorCode.invalidManifest,
          'Origin duplicado: $item',
          subject: 'entry.allowedOrigins',
        );
      }
      values.add(item);
    }
    return List<String>.unmodifiable(values);
  }

  static Uri _parseHttpsUrl(String value, {required String subject}) {
    final uri = Uri.tryParse(value);
    if (value.contains(RegExp(r'\s')) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Se requiere una URL HTTPS absoluta sin credenciales.',
        subject: subject,
      );
    }
    return uri;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key debe ser un entero.',
        subject: key,
      );
    }
    return value;
  }

  static String _requiredString(
    Map<String, Object?> map,
    String key, {
    int? min,
    int? max,
  }) {
    final value = map[key];
    if (value is! String) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key debe ser texto.',
        subject: key,
      );
    }
    final length = value.runes.length;
    if (min != null && length < min || max != null && length > max) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key tiene una longitud inválida.',
        subject: key,
      );
    }
    return value;
  }

  static String? _optionalString(
    Map<String, Object?> map,
    String key, {
    int? max,
  }) {
    if (!map.containsKey(key)) return null;
    final value = map[key];
    if (value is! String) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key debe ser texto.',
        subject: key,
      );
    }
    if (max != null && value.runes.length > max) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key es demasiado largo.',
        subject: key,
      );
    }
    return value;
  }

  static Map<String, Object?> _requiredMap(
    Map<String, Object?> map,
    String key,
  ) {
    final value = map[key];
    if (value is! Map<dynamic, dynamic>) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        '$key debe ser un objeto.',
        subject: key,
      );
    }
    return Map<String, Object?>.from(value);
  }

  static void _rejectUnknown(
    Map<String, Object?> map,
    Set<String> known,
    String subject,
  ) {
    final unknown = map.keys.where((key) => !known.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw ExtensionException(
        ExtensionErrorCode.invalidManifest,
        'Campos desconocidos en $subject: ${unknown.join(', ')}',
        subject: subject,
      );
    }
  }
}
