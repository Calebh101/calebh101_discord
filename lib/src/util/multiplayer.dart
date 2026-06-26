import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

class GameData {
  final String name;
  final int minPlayers;
  final int maxPlayers;
  final String description;

  GameData(this.name, {required this.minPlayers, required this.maxPlayers, required this.description});
}

List<GameData> _gameCatalog = [];
List<GameData> get gameCatalog => _gameCatalog;

void registerGame(GameData game) {
  _gameCatalog.add(game);
  Logger.print("Games", "Registered game: ${game.name}");
}

enum PlayerType {
  user,
  bot,
}

enum BotPersonality {
  safe,
  average,
  risky,
}

class GameProfile {
  final PlayerDetails details;

  GameProfile({required this.details});

  factory GameProfile.user({required User user, required DmChannel channel}) {
    return GameProfile(details: UserPlayerDetails(user: user, channel: channel));
  }

  factory GameProfile.bot() {
    return GameProfile(details: BotPlayerDetails());
  }

  String get formattedDisplayName => details.formattedDisplayName;
  User? get user => details is UserPlayerDetails ? (details as UserPlayerDetails).user : null;
  DmChannel? get channel => details is UserPlayerDetails ? (details as UserPlayerDetails).channel : null;

  Snowflake get id => switch (type) {
    .user => (details as UserPlayerDetails).user.id,
    .bot => (details as BotPlayerDetails).id,
  };

  bool get isUser => details is UserPlayerDetails;
  bool get isBot => details is BotPlayerDetails;
  PlayerType get type => isUser ? .user : (isBot ? .bot : throw UnimplementedError("Invalid details type: ${details.runtimeType}"));

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is GameProfile && other.details == details);
  }

  @override
  int get hashCode => details.hashCode;

  @override
  String toString() {
    return "GameProfile(details: $details)";
  }
}

abstract class PlayerDetails {
  String get formattedDisplayName;

  const PlayerDetails();
}

class BotPlayerDetails extends PlayerDetails {
  late String name;
  late Snowflake id;
  late BotPersonality personality;

  BotPlayerDetails() {
    id = Snowflake(Random().nextInt(9999 - 1111 + 1) + 1111);
    name = "${npcNameOptions1.ro()}${npcNameOptions2.ro()}$id";
    personality = .values.random();
  }

  @override
  String get formattedDisplayName => "*$name* (bot)";

  @override
  String toString() {
    return "BotPlayerDetails(id: $id, name: $name, personality: $personality)";
  }
}

class UserPlayerDetails extends PlayerDetails {
  final User user;
  final DmChannel channel;

  @override
  String get formattedDisplayName => "*${user.globalName ?? user.username}*";

  const UserPlayerDetails({required this.user, required this.channel});

  @override
  String toString() {
    return "UserPlayerDetails(${user.id}, ${user.username}, ${channel.id})";
  }

  @override
  int get hashCode => user.hashCode ^ channel.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is UserPlayerDetails && other.user.id == user.id);
  }
}

class GameContext<T extends GameProfile> {
  final T? player;
  final int turnIndex;
  final int? previousTurnIndex;

  const GameContext({required this.turnIndex, required this.previousTurnIndex, required this.player});
}

class NewGameProfileDetails {
  final PlayerDetails details;

  const NewGameProfileDetails({required this.details});

  factory NewGameProfileDetails.user({required User user, required DmChannel channel}) {
    return NewGameProfileDetails(details: UserPlayerDetails(user: user, channel: channel));
  }

  factory NewGameProfileDetails.bot() {
    return NewGameProfileDetails(details: BotPlayerDetails());
  }
}

abstract class MultiplayerGame<T extends GameProfile> {
  final User owner;
  final KVStore store;
  final NyxxGateway client;
  final String code;
  final Version version;

  Message? publicMessage;

  MultiplayerGame({required this.client, required this.store, required this.owner, required this.version, this.publicMessage}) : code = List.generate(4, (i) => 'abcdefghijklmnopqrstuvwxyz'[Random().nextInt(26)]).join("");

  @nonVirtual
  Future<String?> init(ChatContext context, KVStore store) async {
    if (stopped) return "This game is not available.";

    final result = await onJoin(context);
    if (result != null) return result;

    final channel = await tryCatchA(() => client.users.createDm(owner.id));
    if (channel == null) return "We couldn't send you a DM.";

    final message = await tryCatchA(() => channel.sendMessage(MessageBuilder(content: "Waiting for you to start the game!\nUse `${getPrintablePrefix(store: store, guildId: null)}startgame $code` to start it.\n\nCode: `$code`\nPlayers: **${[minPlayers, ?maxPlayers].join("-")}**")));
    if (message == null) return "We couldn't send you a message in your DMs.";

    players.add(newGameProfile(NewGameProfileDetails.user(user: owner, channel: channel)));
    initialized = true;
    return null;
  }

  List<T> players = [];
  Message? inviteMessage;

  bool started = false;
  bool ended = false;
  bool stopped = false;
  bool initialized = false;

  int get minPlayers;
  int? get maxPlayers;

  String get name;
  String get description;

  BotCommandPermissions get requiredPermsToStart => BotCommandPermissions.any;

  @nonVirtual
  T get ownerPlayer => players.firstWhere((x) => x.id == owner.id);

  /// [currentIndex] is only null if the game was just started.
  FutureOr<int> getNextTurnIndex(int? currentIndex);

  T newGameProfile(NewGameProfileDetails details);

  /// This is called when a player tries to join, whether on the starting screen or mid-round.
  ///
  /// If the user is not allowed to join, return a non-null `String` as the message that is returned.
  FutureOr<String?> onJoin(ChatContext context);

  /// This is called when a bot player tries to join, whether on the starting screen or mid-round.
  ///
  /// If the user is not allowed to join, return a non-null `String` as the message that is returned.
  FutureOr<String?> onJoinBot();

  FutureOr<void> onLeave(T player) {}

  FutureOr<void> onTurn(GameContext<T> context);

  @nonVirtual
  Future<void> leave(ChatContext context, User user) async {
    if (stopped) return;
    final player = players.firstWhereOrNull((x) => x.id == user.id);
    if (player == null) return context.respondWithError("Player doesn't exist.");
    players.remove(player);

    await runForAllPlayers((p) async {
      await p.channel?.sendMessage(MessageBuilder(content: [
        "${player.formattedDisplayName} left. There are now **${players.length}** players remaining.",
        if (players.length < minPlayers) "This is less than the minimum player count, which is **$minPlayers**. The game may be broken.",
      ].join("\n")));
    });

    await context.respond(MessageBuilder(content: "You left the game."));

    if (players.isEmpty) {
      Logger.print("Game", "Game $name:$code: Stopping game because there are ${players.length} players");
      await onStop();
    }
  }

  @nonVirtual
  Future<void> leaveBot(GameProfile player) async {
    if (stopped) return;
    players.remove(player);

    await runForAllPlayers((player) async {
      await player.channel?.sendMessage(MessageBuilder(content: [
        "${player.formattedDisplayName} left. There are now **${players.length}** players remaining.",
        if (players.length < minPlayers) "This is less than the minimum player count, which is **$minPlayers**. The game may be broken.",
      ].join("\n")));
    });

    if (players.isEmpty) {
      Logger.print("Game", "Game $name:$code: Stopping game because there are ${players.length} players");
      await onStop();
    }
  }

  @nonVirtual
  Future<void> start(ChatContext context) async {
    if (stopped) return;
    assert(initialized, "Please call init() before starting.");

    final i = await getNextTurnIndex(null);
    started = true;

    final message = await context.channel.sendMessage(MessageBuilder(content: "Loading..."));
    publicMessage = message;
    final player = players.elementAtOrNull(i);

    Logger.print("Games", "Starting game $code... (i: $i) (player: $player) (players: $players)");
    return _nextTurn(GameContext(turnIndex: i, previousTurnIndex: null, player: player), i);
  }

  @nonVirtual
  Future<void> nextTurn(GameContext<T> context) async {
    if (stopped) return;
    final i = await getNextTurnIndex(context.turnIndex);
    return _nextTurn(context, i);
  }

  Future<void> _nextTurn(GameContext<T> context, int i) async {
    await onTurn(GameContext<T>(turnIndex: i, previousTurnIndex: context.turnIndex, player: players.elementAtOrNull(i)));
  }

  @nonVirtual
  FutureOr<List<R>> runForAllButCurrentPlayer<R>(GameContext<T> context, FutureOr<R> Function(T player) callback) {
    return Future.wait(players.whereIndexed((i, x) => i != context.turnIndex).map((x) => callback(x)).whereType<Future<R>>());
  }

  @nonVirtual
  FutureOr<List<R>> runForAllPlayers<R>(FutureOr<R> Function(T player) callback) {
    return Future.wait(players.map((x) => callback(x)).whereType<Future<R>>());
  }

  @nonVirtual
  Future<String?> showCode(ChatContext context) async {
    if (stopped) return "This game is not available.";
    return await _showCodeFromDetails(channel: context.channel, embedColor: await getColor(context.member), owner: context.user, prefix: context.getPrintablePrefix(store: store)).to(null);
  }

  @nonVirtual
  Future<void> _showCodeFromDetails({required TextChannel channel, required String prefix, required DiscordColor embedColor, required User owner}) async {
    await channel.sendMessage(MessageBuilder(embeds: [
      EmbedBuilder(
        color: embedColor,
        title: started ? name : "Join Game: $name",
        description: started ? "This game is active." : "$description\n\nUse `${prefix}joingame $code` to join.\nUse `${prefix}startgame $code` to start.",
        fields: [
          EmbedFieldBuilder(name: "Code", value: code.toDiscordCodeString(), isInline: true),
          EmbedFieldBuilder(name: "Owner", value: owner.mention, isInline: true),
          EmbedFieldBuilder(name: "Players", value: "${players.length}/$maxPlayers", isInline: true),
        ],
      ),
    ]));
  }

  @nonVirtual
  Future<void> end() async {
    if (ended || stopped) return;
    setStopped();
    Logger.print("Games", "Game $name:$code ended");
  }

  @nonVirtual
  Future<String?> join(ChatContext context) async {
    if (stopped) return "This game is not available.";
    if (maxPlayers != null && players.length + 1 > maxPlayers!) return "Maximum number of players reached.";

    final result = await onJoin(context);
    if (result != null) return result;

    final channel = await tryCatchA(() => context.client.users.createDm(context.user.id));
    if (channel == null) return "We couldn't send you a DM.";

    final message = await tryCatchA(() => channel.sendMessage(MessageBuilder(content: "Loading...")));
    if (message == null) return "We couldn't send you a message in your DMs.";

    if (maxPlayers != null && players.length + 1 > maxPlayers!) {
      await message.edit(MessageUpdateBuilder(content: "Maximum number of players reached."));
      return "Maximum number of players reached.";
    }

    final player = newGameProfile(NewGameProfileDetails.user(user: context.user, channel: channel));
    players.add(player);

    await message.edit(MessageUpdateBuilder(content: "Waiting for ${ownerPlayer.formattedDisplayName} to start the game!"));
    await ownerPlayer.channel?.sendMessage(MessageBuilder(content: "**${player.formattedDisplayName}** joined!\nPlayers: **${[players.length, ?maxPlayers].join("/")}**"));
    return null;
  }

  @nonVirtual
  Future<(bool, String?)> joinBot({bool alert = true}) async {
    if (stopped) return (false, "This game is not available.");
    if (maxPlayers != null && players.length + 1 > maxPlayers!) return (false, "Maximum number of players reached.");

    final result = await onJoinBot();
    if (result != null) return (false, result);
    if (maxPlayers != null && players.length + 1 > maxPlayers!) return (false, "Maximum number of players reached.");

    final player = newGameProfile(NewGameProfileDetails.bot());
    players.add(player);

    if (alert) await ownerPlayer.channel?.sendMessage(MessageBuilder(content: "**${player.formattedDisplayName}** joined!\nPlayers: **${[players.length, ?maxPlayers].join("/")}**"));
    return (true, (player.details as BotPlayerDetails).name);
  }

  @nonVirtual
  FutureOr<void> updatePublicMessage(MessageUpdateBuilder builder) async {
    await publicMessage?.update(builder);
  }

  void setStopped() {
    stopped = true;
    ended = true;
    MultiplayerPlugin.games.remove(code);
  }

  @nonVirtual
  FutureOr<void> onStop() async {
    setStopped();
    await updatePublicMessage(MessageUpdateBuilder(content: "This game has been stopped.", embeds: []));
  }
}