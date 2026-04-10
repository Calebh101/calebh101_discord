import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class PluginStore {
  List<Plugin> plugins = [];

  PluginStore();

  Future<void> register(Plugin plugin) async {
    plugins.add(plugin);
    Modlog.extraGroupCollections.addAll(await plugin.modlogGroups());
    await plugin.onRegister();
  }

  Future<void> registerAll(Iterable<Plugin> all) async {
    plugins.addAll(all);
    await Future.wait(plugins.map((x) => x.onRegister()));
  }

  Future<void> load(BotContext context) async {
    await Future.wait(plugins.map((x) => x.onClientLoad(context)));
  }

  Future<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) async {
    return (await Future.wait(plugins.map((x) => x.commands(plugin, store).toFuture()))).flatten().toList();
  }
}

abstract class Plugin {
  final String id;
  final String name;

  Plugin({required this.id, required this.name});

  Future<void> onRegister() async {}
  Future<void> onClientLoad(BotContext context) async {}
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) => [];
  FutureOr<List<ModlogGroupCollection>> modlogGroups() => [];
}