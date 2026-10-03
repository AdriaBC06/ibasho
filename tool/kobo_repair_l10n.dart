// Repair the extension strings that were mojibaked by Windows PowerShell 5.1
// reading the original UTF-8-without-BOM installer script as an ANSI script.
import 'dart:convert';
import 'dart:io';

const Map<String, String> es = <String, String>{
  'settingsExtensions': 'extensiones',
  'settingsExtensionsHint': 'instala y administra paquetes .ibasho locales',
  'extensionsTitle': 'extensiones',
  'extensionsInstall': 'instalar .ibasho',
  'extensionsWorking': 'trabajando…',
  'extensionsSafetyTitle': 'contenido local, permisos mínimos',
  'extensionsSafetyBody':
      'Esta versión solo instala content-pack sin permisos ni código ejecutable. Cada paquete se valida y queda aislado por extensión.',
  'extensionsEmptyTitle': 'no hay extensiones instaladas',
  'extensionsEmptyBody': 'instala un paquete .ibasho local para empezar',
  'extensionsEnabled': 'activa',
  'extensionsDisabled': 'desactivada',
  'extensionsVersion': 'versión {version}',
  'extensionsPublisher': 'por {publisher}',
  'extensionsVersionCount':
      '{count, plural, =1{1 versión instalada} other{{count} versiones instaladas}}',
  'extensionsTrustLocalUnsigned': 'instalación local · sin firma del editor',
  'extensionsVersions': 'versiones',
  'extensionsRemove': 'quitar',
  'extensionsRemoveTitle': '¿quitar {name}?',
  'extensionsRemoveBody':
      'se borrarán todas las versiones instaladas de esta extensión. esta acción no afecta a tu cuenta de Ibasho.',
  'extensionsRemoved': '{name} se ha quitado',
  'extensionsInstalled': '{name} {version} instalado',
  'extensionsInstallFailed': 'no se pudo instalar: {reason}',
  'extensionsActionFailed': 'no se pudo completar: {reason}',
  'extensionsUnexpectedError': 'ocurrió un error inesperado en extensiones',
  'extensionsPickerFailed': 'no se pudo abrir el selector de archivos',
  'extensionsRollbackTitle': 'versiones de {name}',
  'extensionsRollbackBody':
      'elige otra versión ya instalada. no se descarga nada y puedes volver a cambiarla después.',
  'extensionsActiveVersion': '{version} · activa',
  'extensionsRollbackDone': '{name} vuelve a {version}',
  'extensionsLoadFailed': 'no se pudieron leer las extensiones instaladas',
};

const Map<String, String> en = <String, String>{
  'settingsExtensions': 'extensions',
  'settingsExtensionsHint': 'install and manage local .ibasho packages',
  'extensionsTitle': 'extensions',
  'extensionsInstall': 'install .ibasho',
  'extensionsWorking': 'working…',
  'extensionsSafetyTitle': 'local content, minimal permissions',
  'extensionsSafetyBody':
      'This version only installs content-pack packages with no permissions and no executable code. Every package is validated and isolated per extension.',
  'extensionsEmptyTitle': 'no extensions installed',
  'extensionsEmptyBody': 'install a local .ibasho package to get started',
  'extensionsEnabled': 'enabled',
  'extensionsDisabled': 'disabled',
  'extensionsVersion': 'version {version}',
  'extensionsPublisher': 'by {publisher}',
  'extensionsVersionCount':
      '{count, plural, =1{1 installed version} other{{count} installed versions}}',
  'extensionsTrustLocalUnsigned':
      'local install · publisher signature not verified',
  'extensionsVersions': 'versions',
  'extensionsRemove': 'remove',
  'extensionsRemoveTitle': 'remove {name}?',
  'extensionsRemoveBody':
      'all installed versions of this extension will be deleted. this does not affect your Ibasho account.',
  'extensionsRemoved': '{name} was removed',
  'extensionsInstalled': 'installed {name} {version}',
  'extensionsInstallFailed': 'could not install: {reason}',
  'extensionsActionFailed': 'could not complete the action: {reason}',
  'extensionsUnexpectedError': 'an unexpected extensions error occurred',
  'extensionsPickerFailed': 'could not open the file picker',
  'extensionsRollbackTitle': 'versions of {name}',
  'extensionsRollbackBody':
      'choose another version that is already installed. nothing is downloaded and you can switch again later.',
  'extensionsActiveVersion': '{version} · active',
  'extensionsRollbackDone': '{name} is back on {version}',
  'extensionsLoadFailed': 'installed extensions could not be read',
};

Future<void> repair(String path, Map<String, String> values) async {
  final file = File(path);
  final raw = jsonDecode(await file.readAsString());
  if (raw is! Map<String, dynamic>) {
    stderr.writeln('Invalid ARB: $path');
    exitCode = 65;
    return;
  }
  for (final entry in values.entries) {
    if (!raw.containsKey(entry.key)) {
      stderr.writeln('Missing extension key ${entry.key} in $path');
      exitCode = 65;
      return;
    }
    raw[entry.key] = entry.value;
  }
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(raw)}\n',
    flush: true,
  );
  stdout.writeln('Repaired UTF-8 strings: $path');
}

Future<void> main() async {
  await repair('lib/l10n/app_es.arb', es);
  await repair('lib/l10n/app_en.arb', en);
}
