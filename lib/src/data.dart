import 'dart:convert';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

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

class KVStore {
  final Database _db;

  KVStore(String path) : _db = sqlite3.open(path) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS kv (
        scope TEXT NOT NULL,
        id    TEXT NOT NULL,
        key   TEXT NOT NULL,
        value TEXT,
        PRIMARY KEY (scope, id, key)
      )
    ''');
  }

  dynamic get(String scope, String id, String key) {
    final result = _db.select(
      'SELECT value FROM kv WHERE scope=? AND id=? AND key=?',
      [scope, id, key],
    );

    if (result.isEmpty) return null;
    return jsonDecode(result.first['value']);
  }

  void set(String scope, String id, String key, dynamic value) {
    _db.execute(
      'INSERT INTO kv (scope, id, key, value) VALUES (?,?,?,?)'
      ' ON CONFLICT(scope,id,key) DO UPDATE SET value=excluded.value',
      [scope, id, key, jsonEncode(value)],
    );
  }

  void delete(String scope, String id, String key) {
    _db.execute(
      'DELETE FROM kv WHERE scope=? AND id=? AND key=?',
      [scope, id, key],
    );
  }

  Map<String, dynamic> getAll(String scope, String id) {
    final rows = _db.select(
      'SELECT key, value FROM kv WHERE scope=? AND id=?',
      [scope, id],
    );

    return {for (final r in rows) r['key'] as String: jsonDecode(r['value'])};
  }
}

enum Scope {
  server,
  user,
}

class SettingsObject<T> {
  final EntitySettings obj;
  final String key;

  const SettingsObject(this.obj, this.key);

  T? get() {
    return obj.store.get(obj.scope.name, obj.id.toString(), key) as T?;
  }

  void set(T? value) {
    return obj.store.set(obj.scope.name, obj.id.toString(), key, value);
  }

  void delete() {
    return obj.store.delete(obj.scope.name, obj.id.toString(), key);
  }
}

abstract class EntitySettings {
  final KVStore store;
  final Snowflake id;
  final Scope scope;

  const EntitySettings(this.store, this.id, {required this.scope});

  Map<String, dynamic> getAll() {
    return store.getAll(scope.name, id.toString());
  }
}

class ServerSettings extends EntitySettings {
  ServerSettings(super.store, super.id) : super(scope: Scope.server);

  SettingsObject<String> get prefix => SettingsObject<String>(this, "prefix");
  SettingsObject<String> get mainAdmin => SettingsObject<String>(this, "mainAdmin");
  SettingsObject<List> get admins => SettingsObject<List>(this, "admins");
}

class UserSettings extends EntitySettings {
  UserSettings(super.store, super.id) : super(scope: Scope.user);
}

enum IsAdminType {
  role,
  user,
}

bool isAdmin(ServerSettings settings, IsAdminType type, Snowflake id) {
  for (final x in settings.admins.get() ?? []) {
    if (x["type"] == type.name && x["id"] == id.toString()) {
      return true;
    }
  }

  return false;
}