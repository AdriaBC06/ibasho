// Ibasho — catalogo de zonas horarias.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Una zona horaria lista para ensenar.
@immutable
class ZoneEntry {
  const ZoneEntry({required this.id, required this.offset});

  /// Identificador IANA, por ejemplo `Europe/Madrid`. Es lo que se guarda.
  final String id;

  /// Desplazamiento actual respecto a UTC, con el horario de verano aplicado.
  final Duration offset;

  /// `UTC+01:00`, `UTC−03:30`, `UTC±00:00`.
  String get offsetLabel => formatOffset(offset);

  /// `Madrid`, `Buenos Aires`, `Indiana · Indianapolis`.
  String get city {
    final parts = id.split('/');
    final place = parts.length > 1 ? parts.sublist(1) : parts;
    return place.map((p) => p.replaceAll('_', ' ')).join(' · ');
  }

  /// `Europe`, `America`… o cadena vacia para `UTC`.
  String get region => id.contains('/') ? id.split('/').first : '';
}

String formatOffset(Duration offset) {
  if (offset == Duration.zero) return 'UTC±00:00';
  final sign = offset.isNegative ? '−' : '+';
  final minutes = offset.inMinutes.abs();
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return 'UTC$sign$h:$m';
}

/// Regiones geograficas de la base IANA. Deja fuera los alias heredados
/// (`US/…`, `Etc/…`, `SystemV/…`) que duplican zonas y confunden.
const Set<String> _regions = {
  'Africa', 'America', 'Antarctica', 'Asia', 'Atlantic', 'Australia',
  'Europe', 'Indian', 'Pacific',
};

List<ZoneEntry>? _cache;

/// Todas las zonas, ordenadas de UTC−12 a UTC+14 y, dentro de cada
/// desplazamiento, por nombre. Se calcula una vez; la base va embebida en la
/// app, no se pide nada por red.
List<ZoneEntry> allZones({DateTime? at}) {
  if (_cache != null && at == null) return _cache!;
  tzdata.initializeTimeZones();
  final moment = (at ?? DateTime.now()).millisecondsSinceEpoch;
  final zones = <ZoneEntry>[
    const ZoneEntry(id: 'UTC', offset: Duration.zero),
    for (final location in tz.timeZoneDatabase.locations.values)
      if (_regions.contains(location.name.split('/').first))
        ZoneEntry(
          id: location.name,
          offset: location.timeZone(moment).offset,
        ),
  ]..sort((a, b) {
      final byOffset = a.offset.compareTo(b.offset);
      return byOffset != 0 ? byOffset : a.id.compareTo(b.id);
    });
  if (at == null) _cache = zones;
  return zones;
}

/// Busca una zona por su identificador.
ZoneEntry? zoneById(String id) {
  for (final zone in allZones()) {
    if (zone.id == id) return zone;
  }
  return null;
}

/// Filtro de la busqueda: por ciudad, region o desplazamiento (`+1`, `-3`,
/// `utc+5:30`).
bool matchesZone(ZoneEntry zone, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (zone.id.toLowerCase().replaceAll('_', ' ').contains(q)) return true;
  final numeric = RegExp(r'^(?:utc|gmt)?\s*([+\-−])\s*(\d{1,2})(?::?(\d{2}))?$')
      .firstMatch(q);
  if (numeric != null) {
    final sign = numeric.group(1) == '+' ? 1 : -1;
    final minutes = sign *
        (int.parse(numeric.group(2)!) * 60 + int.parse(numeric.group(3) ?? '0'));
    return zone.offset.inMinutes == minutes;
  }
  return zone.offsetLabel.toLowerCase().contains(q);
}
