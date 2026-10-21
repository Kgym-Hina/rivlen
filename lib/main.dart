import 'package:flutter/material.dart';

import 'screens/connection_hub.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RivlenApp());
}

class RivlenApp extends StatefulWidget {
  const RivlenApp({super.key});

  @override
  State<RivlenApp> createState() => _RivlenAppState();
}

class _RivlenAppState extends State<RivlenApp> {
  @override
  void initState() {
    super.initState();
    rivlenThemeController.addListener(_themeChanged);
    rivlenThemeController.load();
  }

  @override
  void dispose() {
    rivlenThemeController.removeListener(_themeChanged);
    super.dispose();
  }

  void _themeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    RivlenColors.setDark(rivlenThemeController.isDark);
    return MaterialApp(
      title: 'Rivlen',
      debugShowCheckedModeBanner: false,
      theme: buildRivlenTheme(),
      home: const ConnectionHubScreen(),
    );
  }
}
