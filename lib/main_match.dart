// Match manager: a separate, dev-only entry point so the store app is unchanged.
//
//   flutter run -t lib/main_match.dart            (add --release for full speed on a phone)
import 'package:ace/match_ui/match_setup_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MatchManagerApp());
}

class MatchManagerApp extends StatelessWidget {
  const MatchManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ACE Match Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const MatchSetupScreen(),
    );
  }
}
