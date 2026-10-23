import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'widgets/mall_glass_card.dart';

import 'services/app_language.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLanguage.init();
  runApp(const MallPilotApp());
}

class MallPilotApp extends StatelessWidget {
  const MallPilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MallPilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: MallGlassStyle.accent,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: MallGlassStyle.pageBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: MallGlassStyle.pageBackground,
          foregroundColor: Color(0xFF0F172A),
          centerTitle: false,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: MallGlassStyle.surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MallGlassStyle.borderColor),
          ),
        ),
      ),
      themeMode: ThemeMode.light,
      home: const HomePage(),
    );
  }
}
