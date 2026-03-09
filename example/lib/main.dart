import 'package:flutter/material.dart';
import 'dart:async';

import 'package:pamina/pamina.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 提前初始化框架引擎，实现秒开体验
  await Pamina.initFramework();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {}

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder:
            (context) => Scaffold(
              appBar: AppBar(title: const Text('Plugin example app')),
              body: Center(
                child: TextButton(
                  onPressed: () {
                    final String userId = "123"; // 标识宿主App业务用户id
                    final String appId = "demoapp"; // 小程序的id
                    final String appPath = ""; // 小程序的本地存储路径
                    Pamina.launchApp(
                      context: context,
                      userId: userId,
                      appId: appId,
                      appPath: appPath,
                    );
                  },
                  child: const Text('点击打开小程序Demo'),
                ),
              ),
            ),
      ),
    );
  }
}
