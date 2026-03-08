import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:mini_app_flutter/mini_app_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _miniAppPlugin = MiniAppPlugin();

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
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Plugin example app')),
          body: Center(
            child: GestureDetector(
              onTap: () {
                final String userId = "123"; // 标识宿主App业务用户id
                final String appId = "demoapp"; // 小程序的id
                final String appPath = ""; // 小程序的本地存储路径
                MiniAppPlugin.launchApp(
                  context: context,
                  userId: userId,
                  appId: appId,
                  appPath: appPath,
                );
              },
              child: const Text('Open Mini App'),
            ),
          ),
        ),
      ),
    );
  }
}
