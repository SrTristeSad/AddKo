import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/addko_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isAndroid) MediaKit.ensureInitialized();
  runApp(const AddKoApp());
}
