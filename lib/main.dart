import 'package:flutter/material.dart';

import 'ui/screens/dashboard_screen.dart';
import 'ui/theme.dart';

/// Application entry point configuring root services and running the desktop app.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PixelControlCenterApp());
}

/// Root application widget configuring global desktop theming and routing.
class PixelControlCenterApp extends StatelessWidget {
  /// Creates a [PixelControlCenterApp] instance.
  const PixelControlCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Control Center',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const DashboardScreen(),
    );
  }
}
