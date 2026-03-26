import 'package:calebh101_discord/calebh101_discord.dart';

final store = KVStore("database.db");

void main(List<String> arguments) async {
  final context = await load(
    botName: "Caleb-Bot",
    version: Version.parse("0.0.0A"),

    owner: calebh101,
    supportServer: calebh101Server,

    primaryColor: DiscordColor.parseHexString("#00FFF0"),
    prefix: mentionOr(prefixFromServerSettings((x) => Calebh101BotServerSettings(store, x.id))),
    permissions: [...GatewayIntents.all],

    store: store,
    settings: BotSettings(),

    commands: (plugin) => [
      BotCommand.converter((plugin) => plugin.getConverter(RuntimeType<GuildTextChannel>(), logWarn: false)),

      pingCommand(),
      messageMe(),
      aboutCommand(store),

      helpCommand((x) => Calebh101BotServerSettings(store, x.id), plugin),
      listAllServerSettings((x) => Calebh101BotServerSettings(store, x.id)),
      killCommand((x) => Calebh101BotServerSettings(store, x.id)),
      echoDebugCommand((x) => Calebh101BotServerSettings(store, x.id)),
      deleteMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),

      ...adminRoles((x) => Calebh101BotServerSettings(store, x.id)),
      ...modLogCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...prefixCommands((x) => Calebh101BotServerSettings(store, x.id)),
    ],
  );

  if (context == null) return;
  Logger.print("main", "Bot loaded!");
}

class Calebh101BotServerSettings extends ServerSettings {
  Calebh101BotServerSettings(super.store, super.id);
}

class Calebh101BotUserSettings extends UserSettings {
  Calebh101BotUserSettings(super.store, super.id);
}

class Calebh101BotUserPerServerSettings extends UserPerServerSettings {
  Calebh101BotUserPerServerSettings(super.store, super.server, super.user);
}