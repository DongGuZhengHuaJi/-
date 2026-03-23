import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class UserProfile {
  static const String _keyUuid = 'user_uuid';
  static const String _keyName = 'user_name';


  static Future<Map<String, String>> loadUserProfile() async{
    final prefs = await SharedPreferences.getInstance();
    String? uuid = prefs.getString(_keyUuid);
    String? name = prefs.getString(_keyName);

    if(uuid == null){
      uuid = const Uuid().v4();
      await prefs.setString(_keyUuid, uuid);
    }


    return {
      _keyUuid: uuid,
      _keyName: name ?? '',
    };
  }
}