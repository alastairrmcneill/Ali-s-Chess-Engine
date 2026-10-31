import 'package:ace/online/supabase_config.dart';
import 'package:ace/providers/game_provider.dart';
import 'package:ace/screens/home_screen.dart';
import 'package:ace/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  if (SupabaseConfig.isConfigured) {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GameProvider>(
      create: (_) => GameProvider(),
      child: MaterialApp(
        title: 'ACE',
        theme: AppTheme.dark(),
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}
