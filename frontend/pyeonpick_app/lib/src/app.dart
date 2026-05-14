import 'package:flutter/material.dart';

import 'core/app_colors.dart';
import 'core/app_environment.dart';
import 'repositories/post_repository.dart';
import 'screens/home_screen.dart';

class PyeonPickApp extends StatelessWidget {
  const PyeonPickApp({super.key});

  @override
  Widget build(BuildContext context) {
    final environment = AppEnvironment.fromDefines();
    final repository = createPostRepository(environment);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '편pick!',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7FCFF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.lime,
          primary: AppColors.lime,
          secondary: AppColors.navy,
          surface: Colors.white,
        ),
      ),
      home: HomeScreen(
        repository: repository,
        environment: environment,
      ),
    );
  }
}
