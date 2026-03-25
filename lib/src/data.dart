import 'dart:convert';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
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
  userPerServer,
}

class SettingsObject<T> {
  final EntitySettings obj;
  final String key;

  final T? Function(dynamic input)? decodeFunction;
  final dynamic Function(T input)? encodeFunction;

  SettingsObject(this.obj, this.key, {this.decodeFunction, this.encodeFunction});

  T? get() {
    try {
      return (decodeFunction ?? cast).call(obj.store.get(obj.scope.name, obj.id.toString(), key));
    } catch (e) {
      Logger.warn("SettingsObject($key, $T)", "Unable to decode: $e");
      return null;
    }
  }

  void set(T? value) {
    try {
      if (value == null) return delete();
      final v = encodeFunction?.call(value) ?? value;
      return obj.store.set(obj.scope.name, obj.id.toString(), key, v);
    } catch (e) {
      Logger.warn("SettingsObject($key, $T)", "Unable to encode value ${value.runtimeType}: $e");
    }
  }

  void delete() {
    return obj.store.delete(obj.scope.name, obj.id.toString(), key);
  }

  static R cast<R>(dynamic input) {
    return input as R;
  }
}

abstract class EntitySettings {
  final KVStore store;
  final String id;
  final Scope scope;

  const EntitySettings(this.store, {required this.id, required this.scope});

  Map<String, dynamic> getAll() {
    return store.getAll(scope.name, id.toString());
  }
}

class ServerSettings extends EntitySettings {
  ServerSettings(super.store, Snowflake id) : super(id: id.toString(), scope: Scope.server);

  SettingsObject<String> get prefix => SettingsObject(this, "prefix");
  SettingsObject<String> get mainAdmin => SettingsObject(this, "mainAdmin");
  SettingsObject<List> get admins => SettingsObject(this, "admins");
  SettingsObject<int> get modlogChannel => SettingsObject(this, "modlogChannel");
  SettingsObject<List<String>> get modlog => SettingsObject(this, "modlogScopes", encodeFunction: (input) => input as List, decodeFunction: (input) => RecursiveCaster.cast<List<String>>(input));
}

class UserSettings extends EntitySettings {
  UserSettings(super.store, Snowflake id) : super(id: id.toString(), scope: Scope.user);
}

class UserPerServerSettings extends EntitySettings {
  UserPerServerSettings(super.store, Snowflake server, Snowflake user) : super(id: "$server.$user", scope: Scope.userPerServer);
}

enum IsAdminType {
  role,
  user,
}

DefinedUser? globalOwner;
DefinedServer? globalSupportServer;
late String globalBotName;

bool isAdmin({required ServerSettings settings, IsAdminType type = IsAdminType.user, required Snowflake id, Snowflake? owner}) {
  if (isOwner(id: id, owner: owner)) return true;
  if (type == IsAdminType.user && settings.mainAdmin.get() == id.toString()) return true;

  for (final x in settings.admins.get() ?? []) {
    if (x["type"] == type.name && x["id"] == id.toString()) {
      return true;
    }
  }

  return false;
}

bool isOwner({required Snowflake id, Snowflake? owner, bool overrideIgnoreOwner = false}) {
  if (!overrideIgnoreOwner && ignoreOwner) return false;
  owner ??= globalOwner?.id;
  if (owner != null && owner == id) return true;
  return false;
}

bool isClaimer({required ServerSettings settings, required Snowflake id}) {
  if (settings.mainAdmin.get() == null) return false;
  if (settings.mainAdmin.get() == id.toString()) return true;
  return false;
}