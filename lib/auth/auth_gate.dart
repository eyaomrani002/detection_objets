import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/login_page.dart';
import '../screen/home_screen.dart';

class AuthGate extends StatelessWidget {
  final List<CameraDescription> cameras;
  const AuthGate({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        print("AuthGate: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, session=${snapshot.data?.session != null}");
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text("Erreur vérification état auth: ${snapshot.error}")),
          );
        }

        if (!snapshot.hasData && snapshot.connectionState == ConnectionState.active) {
          return const Scaffold(
            body: Center(child: Text("État auth inattendu")),
          );
        }

        final session = snapshot.data?.session;
        if (session != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            print("Navigation vers HomeScreen");
            Navigator.of(context, rootNavigator: true).pushReplacement(
              MaterialPageRoute(builder: (context) => HomeScreen(cameras: cameras)),
            );
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            print("Navigation vers LoginPage");
            Navigator.of(context, rootNavigator: true).pushReplacement(
              MaterialPageRoute(builder: (context) => LoginPage(cameras: cameras)),
            );
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
      },
    );
  }
}