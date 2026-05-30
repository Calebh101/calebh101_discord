import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class MultiplayerPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "multiplayer", version: Version.parse("1.0.0A"), description: "Provides commands for the multiplayer game part of this framework.");

  static Map<String, MultiplayerGame> games = {};

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("joingame", "Games", "Join a game by code.", (T context, String code) async {
        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");
        await game.join(context);
      }),

      BotCommand("startgame", "Games", "Start a game, if there's enough players.", (T context, String code) async {
        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");

        if (!isOwner(id: context.user.id) && context.userId != game.owner.id) {
          return context.respondWithError("You're not the owner of this game!");
        }
      }),
    ];
  }
}