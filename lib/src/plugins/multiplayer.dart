import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class MultiplayerPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "multiplayer", version: Version.parse("1.0.0A"), description: "Provides commands for the multiplayer game part of this framework.");

  static Map<String, MultiplayerGame> games = {};
  late KVStore store;

  bool isBanned(User user) {
    return BotSettings(store).blockedFromGames.get().any((x) => x == user.id);
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyString.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    this.store = store;

    return [
      BotCommand("joingame", "Games", "Join a game by code.", (T context, String code) async {
        if (isBanned(context.user)) return context.respondWithError("You can't join this game.");

        final existing = MultiplayerPlugin.games.entries.firstWhereOrNull((x) => !x.value.ended && x.value.players.any((y) => context.user.id == y.user.id))?.value;
        if (existing != null) return context.respondWithError("You're already playing a game of **${existing.name}**!");

        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");

        final result = await game.join(context);
        await context.respond(MessageBuilder(content: result ?? "Game joined."));
      }),

      BotCommand("kickgame", "Games", "Make someone leave any games they're in.", (T context, User user) async {
        final game = games.entries.firstWhereOrNull((x) => x.value.players.any((y) => y.user.id == user.id))?.value;
        if (game == null) return context.respondWithError("This user is not in any games!");
        await game.leave(context, user);
      }, permissionsRequired: .owner),

      BotCommand("leavegame", "Games", "Leave any games you're in.", (T context) async {
        final user = context.user;
        final game = games.entries.firstWhereOrNull((x) => x.value.players.any((y) => y.user.id == user.id))?.value;

        if (game == null) return context.respondWithError("This user is not in any games!");
        await game.leave(context, user);
      }),

      BotCommand("gameblock", "Games", "Block someone from games.", (T context, User user) async {
        final settings = BotSettings(store);
        final value = settings.blockedFromGames.get();
        final contains = value.contains(user.id);

        if (!contains) value.add(user.id);
        else value.remove(user.id);
        settings.blockedFromGames.set(value);

        await context.respond(MessageBuilder(content: "${contains ? "Unbanned" : "Banned"} ${await userToString(user)} from games."));
      }, permissionsRequired: .owner),

      BotCommand("gameblocked", "Games", "Get if someone is blocked from games.", (T context, User user) async {
        final settings = BotSettings(store);
        final value = settings.blockedFromGames.get();
        final contains = value.contains(user.id);

        await context.respond(MessageBuilder(content: "${await userToString(user)} is ${contains ? "**banned**" : "**not** banned"} from games."));
      }),

      BotCommand("startgame", "Games", "Start a game, if there's enough players.", (T context, String code) async {
        if (isBanned(context.user)) return context.respondWithError("You can't start this game.");
        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");

        if (!isOwner(id: context.user.id) && context.userId != game.owner.id) return context.respondWithError("You're not the owner of this game!");
        if (game.players.length < game.minPlayers) return context.respondWithError("Not enough players! You need **${game.minPlayers}-${game.maxPlayers}**, and you currently have **${game.players.length}**.");

        await context.respond(MessageBuilder(content: "Game **$code** started."));
        await game.start(context);
      }),

      BotCommand("listgames", "Games", "List all active games.", (T context) async {
        final games = MultiplayerPlugin.games.entries.where((x) => !x.value.ended).map((x) => x.value);

        await context.respond(MessageBuilder(content: games.isEmpty ? "No active games." : "**${games.length}** active games:\n\n${games.map((game) {
          return "- ${game.name} (${game.code}): ${game.started ? "Active" : "Waiting"}, ${game.players.length} players";
        })}"));
      }),

      BotCommand("getgame", "Games", "Get a game by code.", (T context, String code) async {
        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");
        await game.showCode(context);
      }),

      BotCommand("forcestopgame", "Games", "Stop a game instantly.", (T context, String code) async {
        final game = games[code];
        if (game == null || game.ended) return context.respondWithError("Invalid code.");

        await game.onStop();
        await context.respond(MessageBuilder(content: "Game stopped."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("games", "Games", "Browse the catalog of games.", (T context) async {
        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "All Games",
          color: await getColor(context.member),
          footer: ElementBasedEmbedFooterBuilder(elements: ["${gameCatalog.length} Games"]),
          pages: EmbedPage.generate(gameCatalog.map((game) {
            return EmbedFieldBuilder(name: game.name, value: "**${game.minPlayers}-${game.maxPlayers}** players", isInline: false);
          }).toList()),
        ), settings: ifGuild(store, context.guildId, (id) => ServerSettings(store, id)));
      }),

      BotCommand("game", "Games", "Get a game by name.", (T context, GreedyString input) async {
        final game = gameCatalog.firstWhereOrNull((x) => x.name.toLowerCase() == input.data.trim().toLowerCase());
        if (game == null) return context.respondWithError("Game not found.\nUse `${context.getPrintablePrefix(store: store)}games` to browse games.");

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: game.name,
            description: game.description,
            color: await getColor(context.member),
            footer: EmbedFooterBuilder(text: "${game.minPlayers}-${game.maxPlayers} players"),
          ),
        ]));
      }),
    ];
  }
}

Future<void> newGame<T extends MultiplayerGame>(ChatContext context, {required KVStore store, required T Function() newGame}) async {
  final existing = MultiplayerPlugin.games.entries.firstWhereOrNull((x) => !x.value.ended && x.value.players.any((y) => context.user.id == y.user.id))?.value;
  if (existing != null) return context.respondWithError("You're already playing a game of **${existing.name}**!");

  final perms = BotCommandPermissions.owner;
  if (context.verifyPerms(perms, ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id))) == false) return context.respondWithError("You don't have permission to start this game!\n-# Required perms: `${perms.name}`");

  final game = newGame();
  final result = await game.init(context, store);
  if (result != null) return context.respondWithError(result);

  MultiplayerPlugin.games[game.code] = game;
  await game.showCode(context);
}
