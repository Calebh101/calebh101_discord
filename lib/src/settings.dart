import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

class BotSettingsItem<T> {
  final String key;
  final BotSettings settings;

  const BotSettingsItem(this.settings, this.key);

  T? get() {
    var s = settings.load();
    s ??= {};
    return s[key] as T?;
  }

  Future<T?> getAsync() async {
    var s = await settings.loadAsync();
    s ??= {};
    return s[key] as T?;
  }

  Future<bool> set(T? value) async {
    var s = await settings.loadAsync();
    s ??= {key: value};
    s[key] = value;
    await settings.file.writeAsString(jsonEncode(s));
    return true;
  }
}

class BotSettings {
  final String filename;
  const BotSettings({this.filename = "settings.json"});

  File get file => File(p.join(Directory.current.path, filename));
  BotSettingsItem<String> get botToken => BotSettingsItem<String>(this, "botToken");

  Future<Map<dynamic, dynamic>?> loadAsync() async {
    try {
      final result = await file.readAsString();
      return jsonDecode(result);
    } catch (e) {
      return null;
    }
  }

  Map<dynamic, dynamic>? load() {
    try {
      final result = file.readAsStringSync();
      return jsonDecode(result);
    } catch (e) {
      return null;
    }
  }

  Future<bool> init() async {
    // Meant to be overridden
    return true;
  }

  @nonVirtual
  Future<bool> initCore() async {
    if (await botToken.getAsync() == null) {
      final result = await askForInput(botToken);
      if (result == false) return false;
    }

    if (await botToken.getAsync() == null) return false;
    return true;
  }

  static Future<bool> askForInput<T extends BotSettingsItem<String>>(T item) async {
    stdout.write('Enter value for ${item.key}: >> ');
    final input = stdin.readLineSync();

    if (input == null || input.isEmpty) {
      print('No input provided.');
      return false;
    }

    await item.set(input);
    return true;
  }
}
