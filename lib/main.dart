import 'package:flutter/material.dart';

import 'screens/connection_hub.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RivlenApp());
}

class RivlenApp extends StatelessWidget {
  const RivlenApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Rivlen',
    debugShowCheckedModeBanner: false,
    theme: buildRivlenTheme(),
    home: const ConnectionHubScreen(),
  );
}
