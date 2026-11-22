import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'controller/drive_controller.dart';
import 'ui/console_screen.dart';
import 'ui/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Landscape, two-handed. Immersive where the OS allows it; this does not
  // block every system gesture and the app does not claim that it does.
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  runApp(const WolveBotApp());
}

class WolveBotApp extends StatefulWidget {
  const WolveBotApp({super.key});

  @override
  State<WolveBotApp> createState() => _WolveBotAppState();
}

class _WolveBotAppState extends State<WolveBotApp> {
  final DriveController _controller = DriveController();
  bool _booted = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wolve Bot Pro Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF00E5C7),
        scaffoldBackgroundColor: const Color(0xFF070B0D),
      ),
      home: _booted
          ? ConsoleScreen(controller: _controller)
          : SplashScreen(
              onFinished: () {
                if (!mounted) {
                  return;
                }
                setState(() => _booted = true);
              },
            ),
    );
  }
}
