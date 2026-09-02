import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'pages/home_page.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 前台服务与界面 isolate 的通信端口，需在 runApp 前初始化。
  // flutter_foreground_task 只有安卓实现，桌面端直接跳过。
  if (!kIsWeb && Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }
  runApp(const PomodoroApp());
}

class PomodoroApp extends StatelessWidget {
  const PomodoroApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '专注时光',
        debugShowCheckedModeBanner: false,
        theme: buildPineTheme(),
        home: const HomePage(),
      );
}
