import 'dart:async';
import 'dart:mirrors';

import 'package:calebh101_discord/calebh101_discord.dart';

class PluginStore {
  List<BotPlugin> plugins = [];

  PluginStore();

  Future<void> register(BotPlugin plugin) async {
    Logger.print("PluginStore", "Registering plugin ${plugin.id} ${plugin.version}...");
    plugins.add(plugin);
    plugin.pluginStore = this;
    Modlog.addExtraGroups(await plugin.modlogGroups());
    await plugin.onRegister();
  }

  Future<void> registerAll(Iterable<BotPlugin> all) async {
    await Future.wait(all.map((x) => register(x)));
  }

  Future<void> load(BotContext context) async {
    await Future.wait(plugins.map((x) => x.onClientLoad(context).toFuture()));
  }

  Future<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) async {
    return (await Future.wait(plugins.map((x) => x.commands<T>(plugin, store).toFuture()))).flatten().toList();
  }

  Future<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) async {
    final results = (await Future.wait(plugins.map((x) => x.converters(plugin, store).toFuture()))).flatten().toList();
    Logger.print("PluginStore", "Found ${results.length} converters: ${results.join(", ")}");
    return results;
  }
}

class BotPluginInfo {
  final String id;
  final String description;
  final Version version;

  const BotPluginInfo({required this.id, required this.version, required this.description});
}

abstract class CommandRegisterable {
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) => [];
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) => [];
}

@Deprecated("Use BotPlugin and define getInfo.")
abstract class BotPluginLegacy extends BotPlugin {
  final String _id;
  final Version _version;

  BotPluginLegacy({required String id, required Version version}) : _id = id, _version = version;

  @override
  get info {
    return BotPluginInfo(id: _id, version: _version, description: "A bot plugin (legacy mode).");
  }
}

abstract class BotPlugin extends CommandRegisterable {
  late String className;
  late PluginStore pluginStore;

  BotPlugin() {
    className = MirrorSystem.getName(reflect(this).type.simpleName);
  }

  BotPluginInfo get info;
  FutureOr<void> onRegister() async {}
  FutureOr<void> onClientLoad(BotContext context) async {}

  String get id => info.id;
  Version get version => info.version;
  String get description => info.description;

  /// Template:
  ///
  /// ```dart
  /// {
  ///   ModlogGroup.all: (levelBelow) => {...levelBelow},
  ///   ModlogGroup.normal: (levelBelow) => {...levelBelow},
  ///   ModlogGroup.quiet: (levelBelow) => {...levelBelow},
  ///   ModlogGroup.off: (_) => {},
  /// }
  /// ```
  FutureOr<List<ModlogGroupCollection>> modlogGroups() => [];

  @override
  String toString() {
    return "Plugin(id: $id, version: $version)";
  }
}