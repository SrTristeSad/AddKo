import 'package:flutter/material.dart';

import '../core/repositories/application/repository_registry.dart';
import '../features/launcher/launcher_page.dart';
import 'addko_theme.dart';

class AddKoApp extends StatefulWidget {
  const AddKoApp({super.key});

  @override
  State<AddKoApp> createState() => _AddKoAppState();
}

class _AddKoAppState extends State<AddKoApp> {
  late final RepositoryRegistry _repositoryRegistry;

  @override
  void initState() {
    super.initState();
    _repositoryRegistry = RepositoryRegistry();
  }

  @override
  void dispose() {
    _repositoryRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AddKo',
      debugShowCheckedModeBanner: false,
      theme: buildAddKoTheme(),
      home: LauncherPage(repositoryRegistry: _repositoryRegistry),
    );
  }
}
