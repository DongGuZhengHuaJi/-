import 'user_profile.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final TextEditingController _nameController = TextEditingController();
  String _uuid = "";
  bool _isLoading = true;

  @override
  void initState(){
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async{
    final profile = await UserProfile.loadUserProfile();
    setState(() {
      _uuid = profile['user_uuid'] ?? '';
      _nameController.text = profile['user_name'] ?? '';
      _isLoading = false;
    });
  }

  Future<void> handleLogin() async{
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _nameController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('登录成功')),
    );

    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
      builder: (context) => HomePage(userName: _nameController.text, myUuid: _uuid),
    ));
  }

  @override
  Widget build(BuildContext context) {

    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("您的设备专属 ID:", style: TextStyle(color: Colors.grey)),
            SelectableText(_uuid, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '请输入您的名字',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: handleLogin,
                child: const Text('进入应用'),
              ),
            )
          ],
        ),

      )
    );
  }
}
