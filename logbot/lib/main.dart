import 'dart:convert';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';

final store = KVStore("database.db");
final tokens = BotTokenStore("settings.json");
final plugins = PluginStore();

void main(List<String> arguments) async {
  BotCommand.disableGroups();
  BotCommand.commandType = CommandType.slashOnly;

  Modlog.addExtraGroup({
    ModlogGroup.all: (levelBelow) => {...levelBelow},
    ModlogGroup.normal: (levelBelow) => {...levelBelow},
    ModlogGroup.quiet: (levelBelow) => levelBelow,
  });

  await plugins.registerAll([
    AdminPlugin(),
    BotManagePlugin(),
    HelpPlugin(),
    IgnorePlugin(),
    MessagesPlugin(),
    PrefixPlugin(),
    StatsPlugin(),
    ModlogPlugin(),
    RestrictCommandsPlugin(),
    DebugPlugin(),
  ]);

  final context = await load(
    botName: "Logbot",
    version: Version.parse("0.0.0A"),
    primaryColor: DiscordColor.parseHexString("#AA4444"),

    owners: [calebh101],
    supportServer: null,

    permissions: [...GatewayIntents.all],
    tokens: tokens.single(),
    plugins: plugins,
    prefix: prefixFromServerSettings((g) => ServerSettings(store, g.id)),
    settings: BotSettings(store),
    store: store,

    args: arguments,
    argParser: (parser) => defaultArgParser(),
  );

  Logger.print("Logbot", "Bot loaded: ${context.runtimeType}");
  final server = await ServerSocket.bind('127.0.0.1', logbotPort);
  Logger.print("Logbot", 'Listening on ${server.address.address}:${server.port}');

  await for (Socket client in server) {
    handleClient(client);
  }
}

void handleClient(Socket client) {
  client
    .cast<List<int>>()
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .listen((String line) {
      if (line.trim().isEmpty) return;
      try {
        final json = jsonDecode(line);
        handleInput(Log.fromJson(json));
      } catch (e) {
        Logger.warn("Socket", 'Bad JSON: $e');
      }
    });
}

List<Log> logBuffer = [];

void handleInput(Log log) {}