// Ibasho — configuracion inyectada en tiempo de compilacion.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

/// Configuracion del proyecto Firebase.
///
/// Nada de esto vive en el repositorio: se inyecta con
/// `--dart-define-from-file=.env`. Ver `.env.example` y el README.
abstract final class Env {
  /// Clave publica de la API web. Es publica por diseno; quien protege los
  /// datos son las reglas de la base, no esta clave.
  static const String apiKey = String.fromEnvironment('IBASHO_API_KEY');

  /// URL de la Realtime Database, sin barra final.
  static const String databaseUrl =
      String.fromEnvironment('IBASHO_DATABASE_URL');

  /// Dominio del email sintetico. El usuario nunca lo ve.
  static const String emailDomain =
      String.fromEnvironment('IBASHO_EMAIL_DOMAIN', defaultValue: 'ibasho.top');

  static const bool useEmulator =
      bool.fromEnvironment('IBASHO_USE_EMULATOR', defaultValue: false);

  static const String emulatorHost =
      String.fromEnvironment('IBASHO_EMULATOR_HOST', defaultValue: '127.0.0.1');

  static const int emulatorDbPort =
      int.fromEnvironment('IBASHO_EMULATOR_DB_PORT', defaultValue: 9000);

  static const int emulatorAuthPort =
      int.fromEnvironment('IBASHO_EMULATOR_AUTH_PORT', defaultValue: 9099);

  static const String projectId = String.fromEnvironment('IBASHO_PROJECT_ID');

  /// Raiz de Identity Toolkit. Contra el emulador se antepone su host.
  static String get identityRoot => useEmulator
      ? 'http://$emulatorHost:$emulatorAuthPort/identitytoolkit.googleapis.com/v1'
      : 'https://identitytoolkit.googleapis.com/v1';

  static String get secureTokenRoot => useEmulator
      ? 'http://$emulatorHost:$emulatorAuthPort/securetoken.googleapis.com/v1'
      : 'https://securetoken.googleapis.com/v1';

  /// Raiz de la base de datos, ya resuelta para emulador o produccion.
  static String get databaseRoot => useEmulator
      ? 'http://$emulatorHost:$emulatorDbPort'
      : databaseUrl;

  /// El emulador identifica la base por espacio de nombres en la query.
  static String get databaseQuerySuffix =>
      useEmulator ? 'ns=$projectId-default-rtdb' : '';

  /// Lista de lo que falta, para avisar en pantalla en lugar de reventar.
  static List<String> get missing => <String>[
        if (apiKey.isEmpty) 'IBASHO_API_KEY',
        if (databaseUrl.isEmpty && !useEmulator) 'IBASHO_DATABASE_URL',
        if (useEmulator && projectId.isEmpty) 'IBASHO_PROJECT_ID',
      ];

  static bool get isConfigured => missing.isEmpty;

  /// Traduce el nombre de usuario visible al identificador interno.
  static String emailFor(String username) =>
      '${username.trim().toLowerCase()}@$emailDomain';
}
