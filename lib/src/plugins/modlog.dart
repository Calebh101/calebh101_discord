import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ModlogPlugin extends BotPlugin {
  ModlogPlugin() : super(id: "modlog", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return modLogCommandsX(store);
  }
}