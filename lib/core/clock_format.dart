// Ibasho — formato de reloj segun la preferencia de 12h/24h.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:intl/intl.dart';

/// Da la hora de [time] como texto, en 24 h ("HH:mm") o en 12 h con AM/PM
/// segun [hourFormat24]. El patron de 24 h es fijo, no localizado: el reloj
/// no debe cambiar de forma al cambiar de idioma.
String formatClock(DateTime time, {required bool hourFormat24}) =>
    hourFormat24 ? DateFormat('HH:mm').format(time) : DateFormat('h:mm a').format(time);
