import 'dart:convert';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

enum Scope {
  bot,
  server,
  user,
  userPerServer,
}

String scopeToString(Scope scope) {
  return switch (scope) {
    Scope.bot => "bot",
    Scope.server => "server",
    Scope.user => "user",
    Scope.userPerServer => "userPerServer",
  };
}

bool isStdinLocked = false;

/*class BotSettingsItem<T> {
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
}*/

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

  dynamic get(Scope scope, String id, String key) {
    final result = _db.select(
      'SELECT value FROM kv WHERE scope=? AND id=? AND key=?',
      [scopeToString(scope), id, key],
    );

    if (result.isEmpty) return null;
    return jsonDecode(result.first['value']);
  }

  void set(Scope scope, String id, String key, dynamic value) {
    _db.execute(
      'INSERT INTO kv (scope, id, key, value) VALUES (?,?,?,?)'
      ' ON CONFLICT(scope,id,key) DO UPDATE SET value=excluded.value',
      [scopeToString(scope), id, key, jsonEncode(value)],
    );
  }

  void delete(Scope scope, String id, String key) {
    _db.execute(
      'DELETE FROM kv WHERE scope=? AND id=? AND key=?',
      [scopeToString(scope), id, key],
    );
  }

  Map<String, dynamic> getAll(Scope scope, String id) {
    final rows = _db.select(
      'SELECT key, value FROM kv WHERE scope=? AND id=?',
      [scopeToString(scope), id],
    );

    return {for (final r in rows) r['key'] as String: jsonDecode(r['value'])};
  }

  Map<String, T> getAllForKey<T>(Scope scope, String key) {
    final rows = _db.select(
      'SELECT id, value FROM kv WHERE scope=? AND key=?',
      [scopeToString(scope), key],
    );

    return {for (final r in rows) r['id'] as String: jsonDecode(r['value']) as T};
  }

  Map<String, Map<String, dynamic>> getScope(Scope scope) {
    final rows = _db.select(
      'SELECT id, key, value FROM kv WHERE scope=?',
      [scopeToString(scope)],
    );

    final result = <String, Map<String, dynamic>>{};

    for (final r in rows) {
      final id = r['id'] as String;
      result.putIfAbsent(id, () => {})[r['key'] as String] = jsonDecode(r['value']);
    }

    return result;
  }
}

class SettingsObject<T> {
  final EntitySettings obj;
  final String key;

  final T? Function(dynamic input)? decodeFunction;
  final dynamic Function(T input)? encodeFunction;

  SettingsObject(this.obj, this.key, {this.decodeFunction, this.encodeFunction});

  static SettingsObject<List<T>> list<T>(EntitySettings obj, String key, {T Function(dynamic input)? decodeFunction, dynamic Function(List<T>)? encodeFunction}) {
    return SettingsObject(obj, key, encodeFunction: encodeFunction, decodeFunction: (input) => (input as List?)?.map((x) {
      if (decodeFunction != null) return decodeFunction.call(x);
      return x as T;
    }).toList());
  }

  static SettingsObject<List<Snowflake>> listSnowflake<T>(EntitySettings obj, String key) {
    return list<Snowflake>(obj, key, encodeFunction: (input) => input.map((x) => x.value).toList(), decodeFunction: (input) => input != null ? Snowflake(input) : input);
  }

  static SettingsObject<Snowflake> snowflake<T>(EntitySettings obj, String key) {
    return SettingsObject<Snowflake>(obj, key, encodeFunction: (input) => input.value, decodeFunction: (input) => input != null ? Snowflake(input) : null);
  }

  bool exists() {
    return get() != null;
  }

  T? get() {
    try {
      return (decodeFunction ?? cast).call(obj.store.get(obj.scope, obj.id.toString(), key));
    } catch (e) {
      Logger.warn("SettingsObject($key, $T)", "Unable to decode: $e");
      return null;
    }
  }

  void set(T? value) {
    try {
      if (value == null) return delete();
      final v = encodeFunction?.call(value) ?? value;
      return obj.store.set(obj.scope, obj.id.toString(), key, v);
    } catch (e) {
      Logger.warn("SettingsObject($key, $T)", "Unable to encode value ${value.runtimeType}: $e");
    }
  }

  void delete() {
    return obj.store.delete(obj.scope, obj.id.toString(), key);
  }

  static R cast<R>(dynamic input) {
    return input as R;
  }
}

class SettingsObjectNotNull<T> extends SettingsObject<T> {
  final T Function() defaultFunction;
  SettingsObjectNotNull(super.obj, super.key, {super.encodeFunction, super.decodeFunction, required this.defaultFunction});

  @override
  T get() {
    return super.get() ?? defaultFunction.call();
  }
}

abstract class EntitySettings {
  final KVStore store;
  final String id;
  final Scope scope;

  const EntitySettings(this.store, {required this.id, required this.scope});

  Map<String, dynamic> getAll() {
    return store.getAll(scope, id.toString());
  }

  static bool askForInput<T extends SettingsObject<String>>(T item) {
    final input = ask(item.key);
    if (input == null) return false;
    item.set(input);
    return true;
  }

  static String? ask(String key) {
    isStdinLocked = true;
    stdin.echoMode = true;
    stdin.lineMode = true;

    stdout.write('Enter value for $key: >> ');
    final input = stdin.readLineSync();

    if (input == null || input.trim().isEmpty) {
      Logger.error("EntitySettings", 'No input provided.');
      return null;
    }

    stdin.echoMode = false;
    stdin.lineMode = false;
    isStdinLocked = false;
    return input;
  }

  static Future<String?> getFromLocalFile<T extends SettingsObject<String>>(T item) async {
    try {
      return (await File("${item.key}.setting").readAsString()).trim();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setFromLocalFile<T extends SettingsObject<String>>(T item) async {
    final value = await () async {
      try {
        return (await File("${item.key}.setting").readAsString()).trim();
      } catch (_) {
        return null;
      }
    }();

    if (value != null) {
      item.set(value);
      return true;
    } else {
      return false;
    }
  }
}

class BotSettings extends EntitySettings {
  BotSettings(super.store) : super(id: "_", scope: Scope.server);

  @Deprecated("Use BotTokenStore instead.")
  SettingsObject<List<Snowflake>> get ignored => SettingsObject(this, "ignored", encodeFunction: (input) => input.map((x) => x.value).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Snowflake(x)).toList());
  SettingsObject<(Snowflake client, Snowflake channel, Snowflake user)> get whoRestartedMe => SettingsObject(this, "whoRestartedMe", encodeFunction: (input) => [input.$1.value, input.$2.value, input.$3.value], decodeFunction: (input) => input is List ? (Snowflake(input[0]), Snowflake(input[1]), Snowflake(input[2])) : null);

  Future<bool> init() async {
    // Meant to be overridden
    return true;
  }

  @nonVirtual
  Future<bool> initCore() async {
    return true;
  }
}

T? ifGuild<T extends ServerSettings>(KVStore store, Snowflake? id, T Function(Snowflake id) create) => id != null ? create.call(id) : null;

class ServerSettings extends EntitySettings {
  ServerSettings(super.store, Snowflake id) : super(id: id.toString(), scope: Scope.server);

  SettingsObjectNotNull<String> get prefix => SettingsObjectNotNull(this, "prefix", defaultFunction: () => defaultPrefix);
  SettingsObject<String> get mainAdmin => SettingsObject(this, "mainAdmin");
  SettingsObject<List> get admins => SettingsObject(this, "admins");
  SettingsObject<List> get mods => SettingsObject(this, "mods");
  SettingsObject<int> get modlogChannel => SettingsObject(this, "modlogChannel");
  SettingsObject<List<String>> get modlog => SettingsObject(this, "modlogScopes", encodeFunction: (input) => input as List, decodeFunction: (input) => RecursiveCaster.cast<List<String>>(input));
  SettingsObject<bool> get selfReactAllowed => SettingsObject(this, "selfReactAllowed");
  SettingsObject<int> get banMessageRemovalSeconds => SettingsObject(this, "banMessageRemovalSeconds");
  SettingsObject<int> get kickMessageRemovalSeconds => SettingsObject(this, "kickMessageRemovalSeconds");
  SettingsObject<int> get warningChannel => SettingsObject(this, "warningChannel");
}

class UserSettings extends EntitySettings {
  UserSettings(super.store, Snowflake id) : super(id: id.toString(), scope: Scope.user);
}

class UserPerServerSettings extends EntitySettings {
  UserPerServerSettings(super.store, Snowflake server, Snowflake user) : super(id: getId(server, user), scope: Scope.userPerServer);

  SettingsObject<List<Warn>> get warns => SettingsObject(this, "warns", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Warn.fromJson(x)).toList()?..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  SettingsObjectNotNull<bool> get blocked => SettingsObjectNotNull(this, "blocked", defaultFunction: () => false);

  static String getId(Snowflake server, Snowflake user) {
    return [server, user].join(".");
  }

  static ({Snowflake server, Snowflake user}) parseId(String id) {
    final elements = id.split(".");
    if (elements.length != 2) throw Exception("Unable to parse ID $id: Expected 2 elements, got ${elements.length}.");
    return (server: Snowflake(int.parse(elements[0])), user: Snowflake(int.parse(elements[1])));
  }
}

class BotTokenStore {
  final String file;
  Map<String, String>? data;

  BotTokenStore(this.file) {
    data = load() ?? {};
  }

  Map<String, String>? load() {
    try {
      return RecursiveCaster.cast<Map<String, String>>(jsonDecode(File(file).readAsStringSync()));
    } catch (e) {
      File(file).createSync(recursive: true);
      File(file).writeAsStringSync(jsonEncode({}));

      Logger.print("BotTokenStore", "Wrote to file $file: $e");
      return null;
    }
  }

  bool save(Map<String, String> data) {
    try {
      File(file).createSync(recursive: true);
      File(file).writeAsStringSync(jsonEncode(data));
      return true;
    } catch (e) {
      Logger.warn("BotTokenStore", "Can't save to file $file: $e");
      return false;
    }
  }

  String? get(String key) {
    return data?[key];
  }

  String? getOrAsk(String key) {
    if (data?.containsKey(key) ?? false) {
      return data![key]!;
    } else {
      final input = EntitySettings.ask("BotToken.$key");
      if (input == null) return null;
      set(key, input);
      return input;
    }
  }

  void set(String key, String token) {
    data ??= {};
    data![key] = token;
    save(data!);
  }

  Map<String, String> all(List<String> keys) {
    data ??= {};
    final results = keys.asMap().map((_, x) => MapEntry(x, data![x] ?? getOrAsk(x) ?? (throw Exception("You must provide a token for key $x."))));
    Logger.print("BotTokenStore", "Loaded ${results.length} tokens out of ${keys.length} requested");
    return results;
  }

  Map<String, String> single() {
    return all(["_"]);
  }
}

enum IsAdminType {
  role,
  user,
}

List<DefinedUser>? globalOwners;
DefinedServer? globalSupportServer;
late String globalBotName;

/// First parameter is calling user's ID.
Future<void> Function(Snowflake id, Object? e, {NyxxGateway? client})? onCommandErrorDm;

Future<void> Function(CommandsException e)? onCommandError;

bool isAdmin({required ServerSettings settings, required Member member}) {
  if (isOwner(id: member.id) || isClaimer(settings: settings, id: member.id)) return true;

  for (final x in settings.admins.get() ?? []) {
    if (x["type"] == "user") {
      if (x["id"] == member.id.toString()) {
        return true;
      }
    } else if (x["type"] == "role") {
      if (member.roleIds.any((y) => y.toString() == x["id"])) {
        return true;
      }
    }
  }

  return false;
}

bool isMod({required ServerSettings settings, required Member member}) {
  if (isOwner(id: member.id) || isClaimer(settings: settings, id: member.id) || isAdmin(settings: settings, member: member)) return true;

  for (final x in settings.admins.get() ?? []) {
    if (x["type"] == "user") {
      if (x["id"] == member.id.toString()) {
        return true;
      }
    } else if (x["type"] == "role") {
      if (member.roleIds.any((y) => y.toString() == x["id"])) {
        return true;
      }
    }
  }

  return false;
}

bool isOwner({required Snowflake id, bool overrideIgnoreOwner = false}) {
  if (!overrideIgnoreOwner && ignoreOwner) return false;
  if (globalOwners == null) return false;
  if (globalOwners!.any((x) => x.id == id)) return true;
  return false;
}

bool isClaimer({required ServerSettings settings, required Snowflake id}) {
  if (settings.mainAdmin.get() == null) return false;
  if (settings.mainAdmin.get() == id.toString()) return true;
  return false;
}