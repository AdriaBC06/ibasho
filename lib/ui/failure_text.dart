// Ibasho — traduccion de fallos del backend a lenguaje de persona.
// Copyright (C) 2026 Adrià Bonnin Catalán
// SPDX-License-Identifier: GPL-3.0-or-later

import '../backend/errors.dart';
import '../l10n/gen/app_localizations.dart';
import '../state/session.dart';

String messageForFailure(L l, IbashoFailure failure) => switch (failure) {
      IbashoFailure.network => l.loginErrorNetwork,
      IbashoFailure.invalidCredentials => l.loginErrorCredentials,
      IbashoFailure.accountDisabled => l.loginErrorDisabled,
      IbashoFailure.notAllowed => l.loginErrorNotAllowed,
      IbashoFailure.tooManyAttempts => l.loginErrorTooMany,
      IbashoFailure.permissionDenied => l.errorPermission,
      IbashoFailure.weakPassword => l.changePasswordErrorWeak,
      IbashoFailure.usernameTaken => l.adminErrorUsernameTaken,
      IbashoFailure.tokenExpired => l.sessionExpired,
      IbashoFailure.unknown => l.loginErrorUnknown,
    };

String? messageForSignOut(L l, SignOutReason reason) => switch (reason) {
      SignOutReason.none => null,
      SignOutReason.expired => l.sessionExpired,
      SignOutReason.revoked => l.sessionExpired,
      SignOutReason.notAllowed => l.loginErrorNotAllowed,
    };
