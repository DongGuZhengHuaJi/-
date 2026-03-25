import 'package:flutter/material.dart';
import 'transfer_history_manager.dart';
import 'package:my_first_app/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await TransferHistoryManager.start(); // 加载历史记录
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 250, 250, 250)),
      ),
      home: const LoginPage(),
    );
  }


}
 
