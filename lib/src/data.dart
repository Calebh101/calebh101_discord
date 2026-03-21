import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

bool isStdinLocked = false;

class BotSettingsItem<T> {
  final String key;
  final BotSettings settings;

  const BotSettingsItem(this.settings, this.key);

  T? get({T? Function(dynamic input)? cast}) {
    var s = settings.load();
    s ??= {};
    return cast?.call(s[key]) ?? s[key] as T?;
  }

  Future<T?> getAsync({T? Function(dynamic input)? cast}) async {
    var s = await settings.loadAsync();
    s ??= {};
    return cast?.call(s[key]) ?? s[key] as T?;
  }

  Future<bool> set(T? value) async {
    var s = await settings.loadAsync();
    s ??= {key: value};
    s[key] = value;
    await settings.save(s);
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

  Future<bool> save(Map<dynamic, dynamic> data) async {
    await file.writeAsString(jsonEncode(data));
    return true;
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
    isStdinLocked = true;
    stdin.echoMode = true;
    stdin.lineMode = true;

    stdout.write('Enter value for ${item.key}: >> ');
    final input = stdin.readLineSync();

    if (input == null || input.isEmpty) {
      print('No input provided.');
      return false;
    }

    await item.set(input);
    stdin.echoMode = false;
    stdin.lineMode = false;
    isStdinLocked = false;
    return true;
  }
}

class SettingsItem<T> {
  final String key;
  final EntitySettings settings;

  const SettingsItem(this.settings, this.key);

  T? get(String subkey, {T? Function(dynamic input)? cast}) {
    var s = settings.load(subkey);
    s ??= {};
    return cast?.call(s[key]) ?? s[key] as T?;
  }

  Future<T?> getAsync(String subkey, {T? Function(dynamic input)? cast}) async {
    var s = await settings.loadAsync(subkey);
    s ??= {};
    return cast?.call(s[key]) ?? s[key] as T?;
  }

  Future<bool> set(String subkey, T? value) async {
    var s = await settings.loadAsync(subkey);
    s ??= {key: value};
    s[key] = value;
    await settings.save(subkey, s);
    return true;
  }
}

class EntitySettings {
  final String key;
  final BotSettings botSettings;

  const EntitySettings({required this.botSettings, required this.key});

  Future<Map<dynamic, dynamic>?> loadAsync(String subkey) async {
    try {
      final result = await botSettings.file.readAsString();
      return jsonDecode(result)[key][subkey];
    } catch (e) {
      return null;
    }
  }

  Map<dynamic, dynamic>? load(String subkey) {
    try {
      final result = botSettings.file.readAsStringSync();
      return jsonDecode(result)[key][subkey];
    } catch (e) {
      return null;
    }
  }

  Future<bool> init() async {
    // Meant to be overridden
    return true;
  }

  Future<bool> save(String subkey ,Map<dynamic, dynamic> data) async {
    var s = await botSettings.loadAsync();
    s ??= {};
    s[key] ??= {};
    s[key][subkey] = data;

    await botSettings.save(s);
    return true;
  }
}

class UserSettings extends EntitySettings {
  UserSettings({required super.botSettings}) : super(key: "users");

  SettingsItem<String?> get prefix => SettingsItem<String>(this, "prefix");
}

class ServerSettings extends EntitySettings {
  ServerSettings({required super.botSettings}) : super(key: "servers");
}