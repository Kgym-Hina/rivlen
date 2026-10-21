import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RivlenColors {
  static bool _dark = false;

  static bool get isDark => _dark;

  static void setDark(bool value) => _dark = value;

  static Color get canvas =>
      _dark ? const Color(0xFF171515) : const Color(0xFFF7F5F3);
  static Color get surface =>
      _dark ? const Color(0xFF24201F) : const Color(0xFFFFFEFC);
  static Color get ink =>
      _dark ? const Color(0xFFF4EFEC) : const Color(0xFF282522);
  static Color get muted =>
      _dark ? const Color(0xFFB4AAA4) : const Color(0xFF89837D);
  static Color get line =>
      _dark ? const Color(0xFF3A3230) : const Color(0xFFE8E3DE);
  static const wine = Color(0xFF8B2549);
  static const coral = Color(0xFFEA725F);
  static const green = Color(0xFF4E8C67);
  static const amber = Color(0xFFC58B45);
  static const blue = Color(0xFF4D82A3);
  static const purple = Color(0xFF8266A3);
}

class RivlenThemeController extends ChangeNotifier {
  static const _preferenceKey = 'rivlen.dark_mode';

  bool _isDark = false;

  bool get isDark => _isDark;

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    _isDark = preferences.getBool(_preferenceKey) ?? false;
    RivlenColors.setDark(_isDark);
    notifyListeners();
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    RivlenColors.setDark(_isDark);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_preferenceKey, _isDark);
  }
}

final rivlenThemeController = RivlenThemeController();

ThemeData buildRivlenTheme() {
  final brightness = RivlenColors.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: RivlenColors.wine,
    brightness: brightness,
    primary: RivlenColors.wine,
    surface: RivlenColors.surface,
    error: const Color(0xFFB63838),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: RivlenColors.canvas,
    fontFamily: 'SF Pro Text',
    appBarTheme: AppBarTheme(
      backgroundColor: RivlenColors.canvas,
      foregroundColor: RivlenColors.ink,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RivlenColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RivlenColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RivlenColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: RivlenColors.wine, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: RivlenColors.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: RivlenColors.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: RivlenColors.surface,
    ),
    dividerTheme: DividerThemeData(color: RivlenColors.line),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RivlenColors.ink,
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class RivlenThemeButton extends StatelessWidget {
  const RivlenThemeButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: rivlenThemeController.isDark ? '切换到日间模式' : '切换到夜间模式',
    onPressed: rivlenThemeController.toggle,
    icon: Icon(
      rivlenThemeController.isDark
          ? Icons.light_mode_outlined
          : Icons.dark_mode_outlined,
      size: 20,
    ),
  );
}
