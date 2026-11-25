import 'package:flutter/material.dart';

import 'permissions_view.dart';

bool get hasPermissionsSection => true;

Widget permissionsSection({Key? key}) => PermissionsView(key: key);
