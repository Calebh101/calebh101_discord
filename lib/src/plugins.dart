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
    await Future.wait(plugins.map((x) => x.onClientLoad(context)));
  }

  Future<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) async {
    return (await Future.wait(plugins.map((x) => x.commands(plugin, store).toFuture()))).flatten().toList();
  }

  Future<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) async {
    return (await Future.wait(plugins.map((x) => x.converters(plugin, store).toFuture()))).flatten().toList();
  }
}

abstract class BotPlugin {
  final String id;
  final String? name;
  final Version version;
  late String className;
  late PluginStore pluginStore;

  BotPlugin({required this.id, this.name, required this.version}) {
    className = MirrorSystem.getName(reflect(this).type.simpleName);
  }

  Future<void> onRegister() async {}
  Future<void> onClientLoad(BotContext context) async {}
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) => [];
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) => [];

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
    return "Plugin(id: $id, name: $name, version: $version)";
  }
}