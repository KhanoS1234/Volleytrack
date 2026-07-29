import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme.dart';
import 'views/setup_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const VolleyTrackApp());
}

class VolleyTrackApp extends StatelessWidget {
  const VolleyTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VolleyTrack',
      theme: buildTheme(),
      home: const SetupView(),
      debugShowCheckedModeBanner: false,
    );
  }
}
