import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => AuthService(),
      child: Consumer<AuthService>(
        builder: (ctx, authService, _) {
          return MaterialApp(
            title: 'Chat Seguro',
            theme: ThemeData(
              primarySwatch: Colors.deepPurple,
              visualDensity: VisualDensity.adaptivePlatformDensity,
            ),
            home: FutureBuilder(
              future: authService.tryAutoLogin(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SplashScreen();
                }
                return authService.isAuthenticated
                    ? const HomeScreen()
                    : const LoginScreen();
              },
            ),
          );
        },
      ),
    );
  }
}