# Kōbō / Ibasho Extensions — Threat Model

**Estado:** draft inicial  
**Modelo:** STRIDE + abuso de producto  

## 1. Activos a proteger

Prioridad crítica:

- credenciales y tokens de sesión;
- claves de cifrado y material criptográfico;
- contenido privado de mensajería;
- identidad de la cuenta;
- economía, gacha e inventario;
- relaciones de amistad y datos sociales;
- integridad del cliente Ibasho;
- canal de actualización;

Prioridad alta:

- Tamas y personalización;
- scores y rankings;
- datos privados de cada extensión;
- preferencias;
- privacidad entre extensiones;

Prioridad media:

- disponibilidad del runtime de extensiones;
- rendimiento;
- almacenamiento local;

---

## 2. Fronteras de confianza

```text
Internet / Registry
       │
       ▼
Package Downloader
       │  UNTRUSTED
       ▼
Package Verifier
       │
       ▼
Installed Package
       │  UNTRUSTED CONTENT
       ▼
AddonManager
       │
       ▼
CapabilityBroker
       │  TRUST BOUNDARY
       ▼
Ibasho Core
       │
       ▼
IbashoBackend / Firebase
```

Una extensión permanece no confiable incluso después de instalarse.

La firma cambia su identidad/procedencia, no su nivel de privilegio.

---

## 3. Adversarios

### A1. Autor malicioso de una extensión

Publica deliberadamente un paquete diseñado para robar datos, abusar de permisos o degradar Ibasho.

### A2. Publisher legítimo comprometido

Un atacante roba la clave o la cuenta de distribución de un autor.

### A3. Registry comprometido

El catálogo o servidor de metadata es controlado por un atacante.

### A4. CDN/hosting comprometido

El archivo descargado difiere del publicado originalmente.

### A5. Extensión web comprometida

Una web legítima sufre XSS, takeover de dominio o despliegue malicioso.

### A6. Usuario local con intención de hacer trampas

Modifica memoria, archivos, manifests o mensajes para alterar scores o economía.

### A7. Paquete accidentalmente defectuoso

No hay intención maliciosa, pero provoca DoS, corrupción o consumo excesivo de recursos.

---

## 4. Amenazas principales

### T1. Path traversal durante extracción

**Ataque:** un ZIP contiene `../../session.json`.

**Impacto:** sobrescritura de datos de Ibasho.

**Mitigación:** normalización de rutas, rechazo de `..`, rutas absolutas y symlinks; extracción únicamente en staging.

**Severidad:** crítica.

---

### T2. ZIP bomb

**Ataque:** paquete pequeño que se expande a GB/TB.

**Impacto:** DoS o llenado de almacenamiento.

**Mitigación:** límites de bytes comprimidos, descomprimidos, ratio, número de archivos y streaming con contador.

**Severidad:** alta.

---

### T3. Código arbitrario dentro del proceso

**Ataque:** extensión ejecuta Dart/nativo con privilegios de Ibasho.

**Impacto:** compromiso total.

**Mitigación:** IES 1.x prohíbe módulos ejecutables cargados dinámicamente.

**Severidad:** crítica.

---

### T4. Robo de tokens

**Ataque:** la extensión intenta obtener `idToken` o `refreshToken`.

**Impacto:** suplantación de la cuenta.

**Mitigación:** tokens nunca cruzan CapabilityBroker; sesiones de extensión son efímeras y distintas de las sesiones reales.

**Severidad:** crítica.

---

### T5. Confused deputy

**Ataque:** extensión con permiso débil induce a Ibasho a realizar una operación más poderosa.

**Ejemplo:** `game.report_score` termina indirectamente otorgando monedas.

**Mitigación:** separar reporte de autoridad; cada capability tiene efecto explícito y mínimo; no encadenar efectos sensibles de manera implícita.

**Severidad:** crítica.

---

### T6. Web origin confusion

**Ataque:** una integrated-app redirige a otro dominio o un iframe malicioso usa el bridge.

**Impacto:** acceso no autorizado a capabilities.

**Mitigación:** allowlist exacta de origins, invalidación del bridge al cambiar de origen, handshake ligado a origin y extension ID.

**Severidad:** crítica.

---

### T7. XSS en una integrated-app

**Ataque:** atacante inyecta JavaScript en una app que sí tiene permisos.

**Impacto:** permisos heredados por código hostil.

**Mitigación:** capabilities mínimas; sesiones cortas; CSP recomendada; bridge por mensajes; permisos revocables; publisher puede declarar origins estrictos.

**Severidad:** alta.

---

### T8. Falsificación de score

**Ataque:** usuario o extensión reporta resultados imposibles.

**Impacto:** rankings o economía corruptos.

**Mitigación:** scores de terceros se consideran no autoritativos; recompensas requieren validación independiente.

**Severidad:** alta.

---

### T9. Cross-extension data leak

**Ataque:** una extensión lee el almacenamiento de otra.

**Impacto:** pérdida de privacidad e integridad.

**Mitigación:** namespaces separados administrados por el host; la extensión nunca recibe una ruta real.

**Severidad:** alta.

---

### T10. Permission creep

**Ataque:** actualización solicita permisos significativamente mayores y se activan automáticamente.

**Impacto:** escalada silenciosa de privilegios.

**Mitigación:** todo permiso nuevo requiere reconsentimiento; la actualización permanece instalada pero deshabilitada hasta aprobación si el permiso es obligatorio.

**Severidad:** alta.

---

### T11. Rollback attack

**Ataque:** servidor comprometido entrega una versión antigua vulnerable.

**Impacto:** reintroducción de vulnerabilidades.

**Mitigación:** recordar versión máxima conocida; metadata firmada; en Registry maduro, TUF.

**Severidad:** alta.

---

### T12. Freeze attack

**Ataque:** se bloquean actualizaciones y el cliente cree que una versión vulnerable sigue siendo actual.

**Mitigación:** metadata con expiración cuando existan actualizaciones automáticas.

**Severidad:** media/alta.

---

### T13. Publisher key compromise

**Ataque:** atacante firma malware con una clave robada.

**Mitigación:** revocación de claves, rotación, separación entre clave de publicación y claves críticas, timestamps/metadata futura.

**Severidad:** crítica.

---

### T14. Resource exhaustion

**Ataque:** extensión envía miles de mensajes, guarda demasiado o fuerza operaciones caras.

**Mitigación:** rate limits por extensión y método, cuotas, timeouts, límites de payload y circuit breaker.

**Severidad:** alta.

---

### T15. Manifest parser differential

**Ataque:** Kōbō interpreta el manifest de una forma e Ibasho de otra.

**Mitigación:** JSON Schema compartido, canonical test vectors, parser tests comunes y rechazo de ambigüedades.

**Severidad:** alta.

---

### T16. Unicode spoofing

**Ataque:** extensión se hace pasar visualmente por otra usando caracteres parecidos.

**Mitigación:** ID restringido a ASCII; publisher identity separada del nombre visible; UI muestra publisher e ID en pantallas sensibles.

**Severidad:** media.

---

### T17. Malicious media asset

**Ataque:** archivo de imagen/audio diseñado para explotar decodificadores o consumir recursos extremos.

**Mitigación:** formatos limitados, dimensiones y tamaño máximos, decodificación fuera de rutas sensibles cuando sea posible, dependencias actualizadas.

**Severidad:** media/alta.

---

### T18. Extension impersonation

**Ataque:** atacante publica `Hexebra Official` con otro ID.

**Mitigación:** publisher verification, identidad criptográfica, UI que no usa solo el nombre visible como señal de confianza.

**Severidad:** media.

---

### T19. Revoked extension remains active offline

**Ataque:** extensión dañina sigue funcionando cuando el cliente no ha recibido revocación.

**Mitigación:** revocaciones cacheadas; para casos críticos, expiry de metadata; kill-switch local en nuevas builds.

**Severidad:** alta.

---

### T20. Sensitive telemetry leakage

**Ataque:** logs contienen tokens, mensajes o datos personales.

**Mitigación:** logging estructurado con allowlist; nunca serializar objetos completos del backend.

**Severidad:** alta.

---

## 5. Matriz de capacidades inicial

| Capability | 3rd party | Requiere consentimiento | Autoritativa | MVP |
|---|---:|---:|---:|---:|
| `theme.read` | Sí | No/ligero | No | futura |
| `locale.read` | Sí | No/ligero | No | futura |
| `profile.display_name.read` | Sí | Sí | No | futura |
| `tama.avatar.read` | Sí | Sí | No | futura |
| `storage.private.read` | Sí | Sí | No | futura |
| `storage.private.write` | Sí | Sí | No | futura |
| `game.report_started` | Sí | No | No | futura |
| `game.report_finished` | Sí | No | No | futura |
| `game.report_score` | Sí | Sí | No | futura |
| `currency.write` | No | — | Sí | nunca directo |
| `inventory.write` | No | — | Sí | nunca directo |
| `messages.read` | No | — | Sí/sensible | no previsto |
| `auth.token.read` | No | — | crítico | prohibido |

---

## 6. Principios de implementación segura

1. **Zero trust hacia el paquete.** Instalar no equivale a confiar.
2. **Least privilege.** Ningún permiso implícito por tipo de extensión.
3. **Fail closed.** Si una validación falla, la extensión no se activa.
4. **Atomicidad.** Una actualización incompleta no reemplaza la versión estable.
5. **Revocabilidad.** Todo permiso y sesión puede retirarse.
6. **No ambient authority.** La extensión no hereda filesystem, red, tokens ni backend por estar “dentro” del launcher.
7. **Protocol over implementation.** Nunca exponer providers o clases internas.
8. **User-visible trust.** La UI distingue oficial, publisher verificado y local sin verificar.
9. **No economic trust.** Un cliente controlado por terceros no decide recompensas.
10. **Test adversarially.** Fuzzing de manifests, ZIPs, rutas, mensajes y límites.

---

## 7. Pruebas mínimas antes de habilitar instalación comunitaria

- ZIP Slip corpus.
- ZIP bomb controlada.
- symlink escape.
- path normalization Windows/Linux/Android.
- nombres Unicode conflictivos.
- manifest > 64 KiB.
- 501 archivos.
- imagen > límite.
- URL `http://`.
- origin wildcard.
- capability desconocida.
- capability prohibida.
- actualización que añade permisos.
- downgrade de versión.
- paquete truncado.
- hash incorrecto.
- firma incorrecta.
- mensajes > límite.
- flood de mensajes.
- requestId repetido.
- respuesta tardía tras cerrar sesión.
- bridge intentando operar después de revocación.

---

## 8. Riesgo residual aceptado en el MVP

Para 0.1, el runtime debería aceptar únicamente `content-pack` declarativo.

Con esa restricción, el mayor riesgo se concentra en:

- parser/ZIP;
- assets malformados;
- corrupción local;
- spoofing visual.

No existe todavía una superficie de ejecución remota privilegiada.

Ese es deliberadamente el punto de partida.
