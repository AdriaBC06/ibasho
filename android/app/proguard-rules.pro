# Ibasho — reglas minimas de R8.
# Copyright (C) 2026 Adrià Bonnin Catalán
# SPDX-License-Identifier: GPL-3.0-or-later
#
# El codigo de la app es Dart y R8 no lo toca. Lo unico que hay que salvar es
# lo que se busca por reflexion desde el motor o desde los plugins.

# El motor de Flutter y sus plugins, que se registran por nombre.
-keep class io.flutter.** { *; }
-keep class top.ibasho.app.MainActivity { *; }

# flutter_soloud llama a Dart desde su hilo de audio con ffi; sus clases Java
# no existen, pero si las de audioplayers y battery_plus, que el registrador
# instancia por reflexion.
-keep class xyz.luan.audioplayers.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }

# flutter_secure_storage usa las clases de seguridad de androidx.
-keep class androidx.security.crypto.** { *; }

# El motor trae soporte para componentes diferidos de Play Store, que Ibasho
# no usa (no se distribuye por la tienda). Sin esto R8 falla por clases que no
# estan en el APK.
-dontwarn com.google.android.play.core.**
