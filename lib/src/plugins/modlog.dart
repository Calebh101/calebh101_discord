import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ModlogPlugin extends BotPluginLegacy {
  ModlogPlugin() : super(id: "modlog", version: Version.parse("1.0.0A"));

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    Timer.periodic(.new(minutes: 1), (async) async {
      await Modlog.flush();
    });
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return modLogCommandsX(store);
  }
}