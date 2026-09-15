// Ibasho — contrato del backend.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'models.dart';

/// Todo lo que Ibasho necesita de un servidor.
///
/// Ninguna capa de interfaz sabe que por debajo hay REST contra Firebase. En
/// Android se podra sustituir por una implementacion sobre los SDK nativos sin
/// tocar nada mas.
abstract interface class IbashoBackend {
  // --- Cuentas -----------------------------------------------------------

  /// Inicia sesion con el nombre de usuario visible.
  ///
  /// `knownGeneration` es la ultima generacion de credencial que funciono en
  /// esta maquina; sirve para acertar a la primera. Ver `SignIn`.
  Future<SignIn> signIn({
    required String username,
    required String password,
    int knownGeneration = 1,
  });

  /// Renueva el token de identidad a partir del de refresco.
  Future<AuthTokens> refresh(String refreshToken);

  /// Cambia la contrasena de la sesion en curso y devuelve los tokens nuevos.
  Future<AuthTokens> changePassword({
    required AuthTokens session,
    required String newPassword,
  });

  /// Crea una cuenta **sin tocar la sesion en curso**.
  ///
  /// Es la operacion delicada del panel de administracion: `accounts:signUp`
  /// devuelve una sesion nueva, y si se dejara entrar en el estado de la app
  /// el administrador quedaria desconectado a mitad del alta. Aqui los tokens
  /// devueltos se descartan.
  Future<ProvisionedAccount> provisionAccount({
    required String username,
    required String password,
    int generation = 1,
  });

  // --- Datos -------------------------------------------------------------

  /// Lee un nodo. Con `query`, solo los hijos que cumplen la consulta.
  Future<Object?> read(
    String path, {
    required String idToken,
    bool shallow = false,
    DatabaseQuery? query,
  });

  Future<void> write(String path, Object? value, {required String idToken});

  /// Fusion. Las claves pueden ser rutas (`tamas/x`, `users/y/tamaCount`):
  /// entonces es una escritura multi-ruta, que se aplica entera o no se aplica.
  Future<void> merge(String path, Map<String, Object?> value, {required String idToken});

  Future<void> remove(String path, {required String idToken});

  /// Suscripcion en tiempo real a un nodo.
  ///
  /// El flujo se reconecta solo con retroceso exponencial y tope de 30 s.
  /// `token` se invoca en cada intento para conseguir un token fresco.
  Stream<DatabaseEvent> watch(
    String path, {
    required Future<String> Function() token,
    DatabaseQuery? query,
  });

  // --- Salud -------------------------------------------------------------

  /// Comprueba conectividad real contra el endpoint de la base.
  Future<LinkQuality> probe();

  void dispose();
}
