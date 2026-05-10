import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class GitHubPlugin extends BotPluginLegacy {
  GitHubPlugin() : super(id: "github", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("github", "GitHub", "Send a GitHub repo.", (ChatContext context, String arg1, [String? arg2, GreedyStringList? params]) async {
        final p = params?.data ?? [];
        await context.respond(MessageBuilder(content: "https://gh.calebh101.net${[arg1, ?arg2].map((x) => "/$x").join("")}${p.isNotEmpty ? "?${p.first}${p.sublist(1, p.length).map((x) => "&$x").join("")}" : ""}"));
      }, aliases: ["gh"]),
    ];
  }
}