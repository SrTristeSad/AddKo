import 'package:flutter/material.dart';

import '../features/launcher/launcher_page.dart';
import 'addko_theme.dart';

class AddKoApp extends StatelessWidget {
  const AddKoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AddKo',
      debugShowCheckedModeBanner: false,
      theme: buildAddKoTheme(),
      home: const LauncherPage(),
    );
  }
}
