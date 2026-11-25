import 'package:flutter/material.dart';
import '../providers/locale_provider.dart';
import 'package:glitch/gen_l10n/app_localizations.dart';

export 'package:glitch/gen_l10n/app_localizations.dart';

extension L10nExt on BuildContext {
  S get s => S.of(this);
}

S get appStrings => lookupS(localeProvider.locale);
