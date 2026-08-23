import 'package:recordo/core/storage/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Bootstrap {
  Bootstrap._();

  static late final LocalStore store;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    store = LocalStore(prefs);
  }
}
