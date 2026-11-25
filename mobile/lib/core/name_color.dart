import 'package:flutter/painting.dart' show Color;

import '../theme/app_theme.dart';
import 'avatar_color.dart';

Color nameColor(String? raw) => parseAvatarColor(raw) ?? GlitchColors.textPrimary;
