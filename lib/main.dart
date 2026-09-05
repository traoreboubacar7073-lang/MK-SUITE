import 'package:flutter/material.dart';
import 'data/repository.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MkSuiteApp());
}

class MkSuiteApp extends StatefulWidget {
  const MkSuiteApp({super.key});

  @override
  State<MkSuiteApp> createState() => _MkSuiteAppState();
}

class _MkSuiteAppState extends State<MkSuiteApp> {
  @override
  void initState() {
    super.initState();
    // Purge silencieuse des éléments de la corbeille de plus de 30 jours, à
    // chaque démarrage — même politique que la version ordinateur
    // (db.purge_corbeille_ancienne(jours=30) dans main.py).
    CorbeilleRepository().purgeExpired();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MK Suite',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      darkTheme: AppTheme.build(),
      themeMode: ThemeMode.dark,
      home: const MainShell(),
    );
  }
}
