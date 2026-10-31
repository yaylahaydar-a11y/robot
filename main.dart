import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:provider/provider.dart';
import 'providers/bluetooth_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/connect_screen.dart';
import 'screens/dashboard_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const FireBotApp());
}

class FireBotApp extends StatelessWidget {
  const FireBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothProvider()),
      ],
      child: MaterialApp(
        title: 'FireBot Controller',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/connect': (context) => const ConnectScreen(),
          '/dashboard': (context) => const DashboardScreen(),
        },
      ),
    );
  }
}