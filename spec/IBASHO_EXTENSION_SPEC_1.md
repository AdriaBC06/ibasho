# Ibasho Extension Specification 1.0 — Draft

**Estado:** propuesta técnica externa, no oficial  
**Versión del documento:** 1.0-draft.1  
**Objetivo de compatibilidad inicial:** Ibasho 0.9.x+  
**Autores de la propuesta:** proyecto Kōbō  

## 1. Propósito

Ibasho Extension Specification (IES) define una frontera estable entre **Ibasho Core** y extensiones desarrolladas fuera del repositorio principal.

La especificación prioriza, en este orden:

1. seguridad del usuario y de la cuenta;
2. aislamiento entre extensiones;
3. compatibilidad a largo plazo;
4. posibilidad de distribución comunitaria;
5. experiencia de usuario coherente con Ibasho;
6. facilidad para crear extensiones.

IES no convierte a Ibasho en un cargador de código arbitrario. La primera generación de la plataforma se basa en **paquetes declarativos** y, cuando sea necesario, en aplicaciones externas aisladas que se comunican con Ibasho mediante un protocolo de capacidades.

---

## 2. No objetivos de IES 1.0

IES 1.0 **no** pretende:

- cargar archivos `.dart`, `.dll`, `.so`, `.dex`, `.exe` o scripts arbitrarios dentro del proceso de Ibasho;
- permitir acceso directo de una extensión a Firebase;
- exponer `idToken`, `refreshToken`, claves de cifrado, credenciales o rutas privadas de Ibasho;
- permitir que una extensión otorgue monedas, premios, objetos de gacha u otras recompensas autoritativas;
- ofrecer dependencias entre extensiones;
- ofrecer ejecución en segundo plano;
- ofrecer APIs de amigos, mensajería o contenido cifrado;
- definir todavía un marketplace central obligatorio.

Estas exclusiones son deliberadas. Reducen el área de ataque y permiten que la API evolucione sin cargar deuda prematuramente.

---

## 3. Componentes

La arquitectura propuesta separa cuatro proyectos lógicos:

### 3.1 Ibasho Core

La aplicación principal. Conserva la autoridad sobre:

- identidad y sesión;
- Firebase y cualquier backend;
- economía;
- Tamas;
- amigos;
- mensajería;
- clasificación y recompensas;
- permisos de extensiones.

### 3.2 `ibasho-addon-spec`

Repositorio pequeño y estable que contiene:

- esta especificación;
- `manifest.schema.json`;
- ejemplos;
- vectores de prueba;
- changelog del protocolo.

### 3.3 Kōbō

Herramienta independiente para autores de extensiones.

Responsabilidades:

- crear manifiestos;
- validar paquetes;
- calcular hashes;
- inspeccionar permisos;
- empaquetar `.ibasho`;
- firmar paquetes cuando el sistema de firma exista;
- producir diagnósticos reproducibles.

Kōbō **no** decide qué puede hacer una extensión en tiempo de ejecución. Esa autoridad pertenece a Ibasho Core.

### 3.4 Registry

Catálogo opcional para versiones futuras. Contendrá metadatos y referencias a paquetes, pero no será una dependencia del formato local.

---

## 4. Tipos de extensión

IES 1.0 reconoce tres tipos.

### 4.1 `content-pack`

Paquete puramente declarativo. No ejecuta código.

Ejemplos:

- fondos;
- música;
- stickers;
- accesorios;
- niveles;
- temas;
- contenido localizado.

Es el tipo más seguro y el único que debería habilitarse en el primer MVP.

### 4.2 `external-app`

Representa una aplicación o juego externo que Ibasho puede abrir.

El destino puede ser una URL HTTPS o, en versiones futuras, una aplicación instalada identificada mediante un mecanismo específico de plataforma.

En IES 1.0 un `external-app` **no recibe automáticamente ningún dato de Ibasho**.

### 4.3 `integrated-app`

Aplicación externa que participa en un protocolo de mensajes con Ibasho y puede solicitar capacidades explícitas.

IES 1.0 define el modelo de permisos y el formato de mensajes, pero la implementación del bridge puede permanecer deshabilitada hasta una versión posterior de Ibasho.

---

## 5. Identidad de las extensiones

Cada extensión tiene un identificador permanente:

```text
com.justmre.hexebra
```

Reglas:

- ASCII en minúsculas;
- segmentos separados por `.`;
- cada segmento empieza con letra;
- caracteres permitidos: `a-z`, `0-9`, `-`;
- longitud total máxima: 128 caracteres;
- una vez publicado, el ID no debe reutilizarse para otro producto.

El nombre visible puede cambiar. El ID no.

El ID sirve como raíz de:

- permisos;
- almacenamiento;
- actualizaciones;
- configuración;
- telemetría local;
- asociación con una clave de firma futura.

---

## 6. Paquete `.ibasho`

Un `.ibasho` es un archivo ZIP con estructura controlada.

Ejemplo:

```text
com.justmre.hexebra.ibasho
├── manifest.json
├── icon.png
└── assets/
    └── preview.webp
```

### 6.1 Reglas de empaquetado

Un instalador conforme DEBE:

- rechazar rutas absolutas;
- rechazar `..` como segmento de ruta;
- rechazar enlaces simbólicos;
- rechazar archivos especiales;
- rechazar nombres duplicados después de normalización Unicode;
- limitar el número total de entradas;
- limitar el tamaño comprimido y descomprimido;
- verificar que `manifest.json` exista exactamente una vez en la raíz;
- validar el manifiesto antes de copiar assets a la instalación final;
- instalar primero en staging;
- finalizar mediante una operación atómica siempre que la plataforma lo permita.

Valores recomendados iniciales:

- paquete comprimido: máximo 50 MB;
- tamaño descomprimido: máximo 150 MB;
- máximo de archivos: 500;
- `manifest.json`: máximo 64 KiB;
- icono: máximo 2 MiB;
- imágenes raster: máximo 4096 × 4096 px.

Estos límites DEBEN ser configurables internamente sin cambiar la versión del protocolo.

---

## 7. `manifest.json`

El manifiesto es UTF-8 y se valida contra `manifest.schema.json`.

Ejemplo mínimo:

```json
{
  "schema": 1,
  "id": "com.justmre.hexebra",
  "name": "HEXEBRA",
  "version": "1.0.0",
  "publisher": "Mr. E",
  "type": "external-app",
  "compatibility": {
    "ibashoApi": "^1.0",
    "minIbasho": "0.10.0"
  },
  "entry": {
    "url": "https://hexebra.netlify.app/"
  },
  "permissions": [],
  "assets": {
    "icon": "icon.png"
  }
}
```

### 7.1 Campos desconocidos

Los consumidores de IES 1.x DEBEN ignorar campos desconocidos que no estén dentro de objetos marcados como estrictos por el schema.

Esto permite evolución compatible.

### 7.2 Versionado

`version` usa SemVer.

`schema` versiona la estructura del manifiesto.

`compatibility.ibashoApi` versiona el protocolo de integración.

`compatibility.minIbasho` permite exigir una versión mínima de la aplicación anfitriona.

Estas tres versiones no deben confundirse.

---

## 8. Capacidades y permisos

IES utiliza **capabilities**, no acceso a objetos internos.

Una extensión nunca recibe referencias a `User`, `Tama`, `IbashoBackend`, providers de Riverpod ni estructuras de Firebase.

Ejemplos de capacidades futuras:

```text
theme.read
locale.read
profile.display_name.read
tama.avatar.read
storage.private.read
storage.private.write
game.report_started
game.report_finished
game.report_score
```

### 8.1 Denegación por defecto

Toda capacidad está denegada salvo concesión explícita.

Si una extensión solicita una capacidad que Ibasho no conoce, la instalación o activación DEBE fallar de forma segura.

### 8.2 Permisos sensibles

IES 1.0 reserva y prohíbe las siguientes familias para extensiones de terceros:

```text
auth.*
firebase.*
crypto.*
messages.*
friends.write
currency.write
inventory.write
gacha.*
admin.*
```

Un host puede definir capacidades internas con esos nombres, pero no deben concederse a extensiones comunitarias.

### 8.3 Consentimiento

Antes de activar una extensión con permisos no vacíos, Ibasho DEBE mostrar:

- nombre de la extensión;
- publisher;
- capacidades solicitadas;
- explicación humana de cada capacidad;
- cuáles son obligatorias y cuáles opcionales.

Los permisos opcionales pueden denegarse individualmente.

---

## 9. Capability Broker

`CapabilityBroker` es la única puerta entre una extensión y el estado privilegiado de Ibasho.

Principios:

1. valida la identidad de la extensión;
2. comprueba que la extensión está habilitada;
3. comprueba permisos concedidos;
4. valida parámetros;
5. aplica límites de frecuencia;
6. llama a APIs internas estables;
7. filtra la respuesta;
8. registra errores y eventos de seguridad.

El Broker no expone tokens ni rutas de backend.

---

## 10. Protocolo de mensajes

Cuando exista integración bidireccional, IES usa mensajes estructurados.

Petición:

```json
{
  "protocol": 1,
  "requestId": "d3c44a20",
  "method": "theme.get",
  "params": {}
}
```

Respuesta:

```json
{
  "protocol": 1,
  "requestId": "d3c44a20",
  "ok": true,
  "result": {
    "accent": "#D9A441",
    "dark": false,
    "reducedMotion": true
  }
}
```

Error:

```json
{
  "protocol": 1,
  "requestId": "d3c44a20",
  "ok": false,
  "error": {
    "code": "permission_denied",
    "message": "theme.read is not granted"
  }
}
```

### 10.1 Reglas

- `requestId` debe ser opaco y único dentro de la sesión.
- El host debe imponer un tamaño máximo de mensaje.
- Métodos desconocidos fallan con `method_not_found`.
- Parámetros extra no aceptados por el método deben ser rechazados.
- Los mensajes deben tratarse como entrada hostil.
- El bridge debe tener rate limiting.

---

## 11. Sesiones de integración

Una `integrated-app` nunca recibe la sesión real de Ibasho.

Cuando se lance una extensión integrada, Ibasho puede crear un `extension_session` efímero con:

- ID aleatorio criptográficamente seguro;
- extensión asociada;
- conjunto de capacidades concedidas;
- origen autorizado;
- hora de expiración;
- nonce de lanzamiento.

Propiedades recomendadas:

- vida máxima: 10 minutos renovables mientras el canal permanezca abierto;
- invalidación al cerrar la extensión;
- invalidación al cerrar sesión de Ibasho;
- no reutilizable entre extensiones;
- no persistido por la extensión.

---

## 12. Integración web

Un `external-app` con URL debe usar HTTPS.

### 12.1 IES 1.0

El comportamiento recomendado es abrir el destino fuera del contexto privilegiado de Ibasho.

No existe bridge.

### 12.2 Bridge futuro

Si se introduce una WebView integrada:

- cada extensión declara una lista exacta de orígenes permitidos;
- no se permiten comodines de dominio para canales privilegiados;
- los redirects a un origen no autorizado deshabilitan el bridge;
- un iframe no hereda automáticamente privilegios;
- el bridge debe usar mensajería estructurada, no una API nativa genérica expuesta al JavaScript;
- CSP y políticas equivalentes deben recomendarse a los autores.

---

## 13. Almacenamiento

Las extensiones no reciben rutas de archivos.

La API lógica propuesta es:

```text
storage.get(key)
storage.set(key, value)
storage.delete(key)
storage.list(prefix)
```

Cada extensión tiene un namespace aislado:

```text
addons/data/<extension-id>/
```

Cuota recomendada inicial:

- 5 MiB por extensión;
- máximo 64 KiB por valor;
- máximo 10 000 claves.

El host puede ampliar cuotas, nunca reducirlas silenciosamente por debajo del uso existente.

El almacenamiento sensible debe permanecer bajo el control del host.

---

## 14. Scores, logros y economía

### 14.1 Principio de autoridad

**Un reporte de una extensión no es una prueba.**

Una extensión puede informar:

- que una partida comenzó;
- que una partida terminó;
- un score local;
- estadísticas no autoritativas.

Pero un evento generado por una extensión de terceros NO DEBE, por sí mismo:

- entregar monedas;
- entregar gachaken;
- desbloquear inventario con valor económico;
- modificar rankings autoritativos;
- otorgar premios escasos.

### 14.2 Recompensas futuras

Si un juego externo debe generar recompensas, debe existir una verificación independiente, por ejemplo:

- validación servidor-servidor;
- replay verificable;
- lógica determinista validable;
- servidor de partida autoritativo.

---

## 15. Actualización y rollback

Una instalación se considera una transacción.

Proceso recomendado:

```text
Download
  ↓
Verify envelope
  ↓
Extract to staging
  ↓
Validate manifest
  ↓
Validate assets
  ↓
Verify hashes/signature
  ↓
Compatibility check
  ↓
Atomic promote
  ↓
Update installed index
```

Nunca se sobrescribe directamente la versión activa mientras se valida la nueva.

El host debería conservar al menos la versión anterior hasta completar el primer arranque exitoso de la nueva versión.

---

## 16. Integridad y firma

IES 1.0 permite paquetes sin firma para instalación local, pero deben mostrarse como **no verificados**.

Estados de confianza sugeridos:

- `official` — firmado por una clave controlada por el proyecto Ibasho;
- `verified-publisher` — firma válida de un publisher conocido por el registro;
- `local-unsigned` — instalación manual sin identidad verificada.

Una firma demuestra integridad y procedencia, no seguridad funcional.

El sistema de firma futuro debería usar criptografía moderna ampliamente soportada (por ejemplo Ed25519), sin diseñar primitivas propias.

---

## 17. Revocación

La arquitectura debe soportar, aunque el primer MVP no lo implemente todavía:

- revocar una clave de publisher;
- bloquear una versión concreta;
- bloquear una extensión completa;
- desactivar capacidades concretas en una versión vulnerable;
- avisar al usuario sin borrar automáticamente sus datos.

La revocación debe distinguir entre:

```text
compromised
malware
policy_violation
incompatible
publisher_request
```

---

## 18. Registry

El Registry no debe ser una fuente de autoridad para el runtime.

Puede almacenar:

- ID;
- nombre;
- publisher;
- versiones;
- compatibilidad;
- hashes;
- URLs de descarga;
- firmas;
- estado de revocación.

Ibasho debe poder instalar paquetes locales sin Registry.

Cuando existan actualizaciones automáticas, la metadata debe proteger frente a:

- rollback;
- freeze;
- metadata inconsistente;
- repositorio parcialmente comprometido.

Se recomienda adoptar TUF o un diseño basado directamente en sus roles y metadata, en vez de inventar un sistema propio.

---

## 19. Compatibilidad

### 19.1 API

Ibasho debe mantener compatibilidad hacia atrás dentro de la misma major de Extension API.

Ejemplo:

```text
1.0 → 1.1 → 1.5
```

Una extensión que funciona con `^1.0` debe continuar funcionando salvo que use una capability explícitamente deprecada y retirada en una major posterior.

### 19.2 Feature detection

Las extensiones deben poder consultar capacidades disponibles en lugar de inferirlas únicamente por número de versión.

Ejemplo futuro:

```text
host.capabilities()
```

---

## 20. Observabilidad

Ibasho debería mantener logs locales de eventos de extensiones con datos mínimos:

- instalación;
- actualización;
- desinstalación;
- error de validación;
- permiso denegado;
- mensaje inválido;
- rate limit;
- fallo de firma;
- revocación.

No se deben registrar:

- contraseñas;
- tokens;
- contenido de mensajes privados;
- payloads sensibles completos.

---

## 21. Privacidad

Las extensiones no reciben identificadores globales innecesarios.

Si en el futuro necesitan identificar a un usuario de Ibasho, el host debería preferir un identificador **por extensión**, derivado o aleatorio:

```text
extensionUserId(extensionId, account)
```

Así dos extensiones no pueden correlacionar usuarios automáticamente.

---

## 22. Desinstalación

Al desinstalar una extensión:

- se elimina el paquete ejecutable/declarativo;
- se revocan sesiones activas;
- se eliminan permisos concedidos;
- los datos de usuario se conservan por defecto durante un periodo configurable o hasta que el usuario solicite eliminarlos;
- debe existir una opción explícita de “Eliminar también los datos”.

Esto facilita reinstalaciones sin obligar a conservar basura indefinidamente.

---

## 23. Ciclo de vida recomendado

### Kōbō / IES 0.1

- schema;
- parser;
- validator;
- `content-pack`;
- instalación local;
- desinstalación;
- staging y rollback básico.

### 0.2

- `external-app`;
- abrir URLs HTTPS;
- iconos y metadata;
- compatibilidad de versión.

### 0.3

- Capability API solo lectura;
- `theme.read`;
- `locale.read`;
- `profile.display_name.read`;
- `tama.avatar.read`.

### 0.4

- almacenamiento privado;
- eventos de juego no autoritativos;
- cuotas y rate limiting.

### 0.5

- firma de publishers;
- actualización manual firmada;
- rollback robusto;
- revocación.

### 0.6

- Registry comunitario;
- búsqueda;
- autores;
- versiones.

### 1.0

- actualización automática segura;
- metadata tipo TUF;
- API estable;
- política formal de deprecación.

---

## 24. Criterios para aceptar una nueva capability

Toda nueva capability debe responder satisfactoriamente:

1. ¿Puede resolverse sin exponer estado interno?
2. ¿Puede limitarse a una sola extensión?
3. ¿Puede revocarse inmediatamente?
4. ¿Puede rate-limitarse?
5. ¿Su retorno puede minimizar datos?
6. ¿Qué ocurre si la extensión miente?
7. ¿Qué ocurre si la extensión está comprometida?
8. ¿Permite obtener indirectamente un permiso más poderoso?
9. ¿Se puede probar automáticamente?
10. ¿Puede mantenerse durante años sin congelar la arquitectura interna de Ibasho?

Si alguna respuesta crítica es “no”, la capability no debe publicarse todavía.

---

## 25. Regla principal

> **Las extensiones dependen del protocolo de Ibasho; nunca de la implementación interna de Ibasho.**

Ese principio tiene prioridad sobre conveniencia, velocidad de desarrollo o integración visual.
