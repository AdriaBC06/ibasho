// Ibasho — modelo de datos del checkpoint 1.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show Color;

import '../theme/tokens.dart';

/// Juego de tokens de una sesion de Identity Toolkit.
class AuthTokens {
  const AuthTokens({
    required this.uid,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String uid;
  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Se renueva un minuto antes de caducar, como pide el checkpoint.
  DateTime get renewAt => expiresAt.subtract(const Duration(minutes: 1));

  Map<String, Object?> toJson() => {
        'uid': uid,
        'idToken': idToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };

  static AuthTokens fromJson(Map<String, Object?> json) => AuthTokens(
        uid: json['uid']! as String,
        idToken: json['idToken']! as String,
        refreshToken: json['refreshToken']! as String,
        expiresAt: DateTime.parse(json['expiresAt']! as String),
      );

  AuthTokens copyWith({String? idToken, String? refreshToken, DateTime? expiresAt}) =>
      AuthTokens(
        uid: uid,
        idToken: idToken ?? this.idToken,
        refreshToken: refreshToken ?? this.refreshToken,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

/// Entrada de `/allowlist/{authUid}`: una identidad de inicio de sesion.
///
/// Una persona puede tener varias a lo largo del tiempo (cada vez que se le
/// regenera la credencial nace una nueva), pero todas apuntan al mismo
/// `accountId`, que es donde viven sus datos. Asi regenerar una credencial no
/// pierde nada.
class AllowlistEntry {
  const AllowlistEntry({
    required this.uid,
    required this.accountId,
    required this.username,
    required this.createdAt,
    required this.createdBy,
    required this.disabled,
    required this.mustChangePassword,
    required this.generation,
    this.retired = false,
  });

  /// Uid de Identity Toolkit de esta identidad.
  final String uid;

  /// Identificador estable de la cuenta. Nunca cambia; los datos cuelgan de el
  /// en `/users/{accountId}`. En la primera identidad coincide con su uid.
  final String accountId;

  final String username;
  final DateTime createdAt;
  final String createdBy;
  final bool disabled;
  final bool mustChangePassword;

  /// Generacion de la credencial. Ver `SignIn`.
  final int generation;

  /// Identidad sustituida por una credencial regenerada. Queda deshabilitada
  /// para siempre y no se ensena en la lista de cuentas.
  final bool retired;

  static AllowlistEntry fromJson(String uid, Map<Object?, Object?> json) =>
      AllowlistEntry(
        uid: uid,
        accountId: (json['accountId'] as String?) ?? uid,
        username: (json['username'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
        createdBy: (json['createdBy'] as String?) ?? '',
        disabled: (json['disabled'] as bool?) ?? false,
        mustChangePassword: (json['mustChangePassword'] as bool?) ?? false,
        generation: (json['generation'] as num?)?.toInt() ?? 1,
        retired: (json['retired'] as bool?) ?? false,
      );

  Map<String, Object?> toJson() => {
        'accountId': accountId,
        'username': username,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'createdBy': createdBy,
        'disabled': disabled,
        'mustChangePassword': mustChangePassword,
        'generation': generation,
        if (retired) 'retired': true,
      };
}

/// Entrada de `/users/{accountId}/profile`.
class UserProfile {
  const UserProfile({
    required this.username,
    required this.displayName,
    this.statusMessage = '',
    this.birthday = '',
    this.timezone = '',
    this.locale = 'es',
    this.accentColor = '#5BC8F5',
    required this.createdAt,
  });

  final String username;
  final String displayName;
  final String statusMessage;

  /// `AAAA-MM-DD` o cadena vacia si no se ha indicado.
  final String birthday;

  /// Identificador IANA, por ejemplo `Europe/Madrid`.
  final String timezone;

  /// `es` o `en`.
  final String locale;

  /// `#RRGGBB`.
  final String accentColor;

  final DateTime createdAt;

  Color get accent {
    final hex = accentColor.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    if (value == null || hex.length != 6) return T.cyan;
    return Color(0xFF000000 | value);
  }

  /// `AAAA-MM-DD` partido, o `null` si no hay cumpleanos.
  (int year, int month, int day)? get birthdayParts {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(birthday);
    if (m == null) return null;
    return (int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  static UserProfile fromJson(Map<Object?, Object?> json) => UserProfile(
        username: (json['username'] as String?) ?? '',
        displayName: (json['displayName'] as String?) ?? '',
        statusMessage: (json['statusMessage'] as String?) ?? '',
        birthday: (json['birthday'] as String?) ?? '',
        timezone: (json['timezone'] as String?) ?? '',
        locale: (json['locale'] as String?) ?? 'es',
        accentColor: (json['accentColor'] as String?) ?? '#5BC8F5',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
        ),
      );

  Map<String, Object?> toJson() => {
        'username': username,
        'displayName': displayName,
        'statusMessage': statusMessage,
        'birthday': birthday,
        'timezone': timezone,
        'locale': locale,
        'accentColor': accentColor,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  UserProfile copyWith({
    String? displayName,
    String? statusMessage,
    String? birthday,
    String? timezone,
    String? locale,
    String? accentColor,
  }) =>
      UserProfile(
        username: username,
        displayName: displayName ?? this.displayName,
        statusMessage: statusMessage ?? this.statusMessage,
        birthday: birthday ?? this.birthday,
        timezone: timezone ?? this.timezone,
        locale: locale ?? this.locale,
        accentColor: accentColor ?? this.accentColor,
        createdAt: createdAt,
      );
}

/// Credencial recien creada por el panel de administracion. Solo se muestra
/// una vez y no se guarda en ningun sitio.
class ProvisionedAccount {
  const ProvisionedAccount({
    required this.uid,
    required this.username,
    required this.password,
  });

  final String uid;
  final String username;
  final String password;
}

/// Un evento de la base de datos llegado por `text/event-stream`.
class DatabaseEvent {
  const DatabaseEvent({
    required this.path,
    required this.data,
    required this.isPatch,
  });

  /// Ruta relativa al nodo suscrito. `/` cuando es el nodo entero.
  final String path;

  final Object? data;

  /// `true` para `patch` (fusion), `false` para `put` (sustitucion).
  final bool isPatch;
}

/// Calidad de la conexion, medida contra el propio endpoint de la base.
enum LinkQuality { offline, weak, fair, strong }

/// Resultado de un inicio de sesion.
///
/// Ibasho traduce el nombre de usuario visible a un email interno. Cuando el
/// administrador regenera una credencial se emite una **generacion** nueva de
/// ese email (`usuario+2@dominio`), porque Identity Toolkit no deja cambiar la
/// contrasena de otra cuenta sin credenciales de servicio, y la direccion
/// anterior queda ocupada. `generation` es la que ha funcionado; la app la
/// recuerda en local para acertar a la primera la proxima vez.
class SignIn {
  const SignIn({required this.tokens, required this.generation});

  final AuthTokens tokens;
  final int generation;
}
