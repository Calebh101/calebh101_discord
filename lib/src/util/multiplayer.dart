import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

class GameProfile {
  final User user;
  final DmChannel channel;

  GameProfile({required this.user, required this.channel});

  String get formattedDisplayName => "*${user.globalName ?? user.username}*";

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is GameProfile && other.user.id == user.id);
  }

  @override
  int get hashCode => user.hashCode ^ channel.hashCode;

  @override
  String toString() {
    return "GameProfile(${user.id}, ${user.username})";
  }

}

class GameContext<T extends GameProfile> {
  final T player;
  final int turnIndex;
  final int? previousTurnIndex;

  const GameContext({required this.turnIndex, required this.previousTurnIndex, required this.player});
}

class NewGameProfileDetails {
  final User user;
  final DmChannel channel;

  const NewGameProfileDetails({required this.user, required this.channel});
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
  Future<String?> init() async {
    final channel = await tryCatchA(() => client.users.createDm(owner.id));
    if (channel == null) return "We couldn't send you a DM.";

    final message = await tryCatchA(() => channel.sendMessage(MessageBuilder(content: "Loading...")));
    if (message == null) return "We couldn't send you a message in your DMs.";

    players.add(newGameProfile(NewGameProfileDetails(user: owner, channel: channel)));
    initialized = true;
    return null;
  }

  List<T> players = [];
  Message? inviteMessage;

  bool started = false;
  bool ended = false;
  bool initialized = false;

  int get minPlayers;
  int get maxPlayers;

  String get name;
  String get description;

  BotCommandPermissions get requiredPermsToStart => BotCommandPermissions.any;

  @nonVirtual
  T get ownerPlayer => players.firstWhere((x) => x.user.id == owner.id);

  /// [currentIndex] is only null if the game was just started.
  int getNextTurnIndex(int? currentIndex);

  T newGameProfile(NewGameProfileDetails details);

  /// This is called when a player tries to join, whether on the starting screen or mid-round.
  ///
  /// If the user is not allowed to join, return a non-null `String` as the message that is returned.
  FutureOr<String?> onJoin();

  FutureOr<void> onLeave(T player) {}

  FutureOr<void> onTurn(GameContext<T> context);

  @nonVirtual
  Future<void> leave(ChatContext context, User user) async {
    final player = players.firstWhereOrNull((x) => x.user.id == user.id);
    if (player == null) return context.respondWithError("Player doesn't exist.");
    players.remove(player);

    await runForAllPlayers((player) async {
      await player.channel.sendMessage(MessageBuilder(content: [
        "${player.formattedDisplayName} left. There are now **${players.length}** players remaining.",
        if (players.length < minPlayers) "This is less than the minimum player count, which is **$minPlayers**. The game may be broken.",
      ].join("\n")));
    });

    await context.respond(MessageBuilder(content: "You left the game."));
  }

  @nonVirtual
  Future<void> start(ChatContext context) async {
    assert(initialized, "Please call init() before starting.");
    final i = getNextTurnIndex(null);
    started = true;

    final message = await context.channel.sendMessage(MessageBuilder(content: "Waiting for you to start the game..."));
    publicMessage = message;
    final player = players[i];

    Logger.print("Games", "Starting game $code... (i: $i) (player: $player) (players: $players)");
    return _nextTurn(GameContext(turnIndex: i, previousTurnIndex: null, player: player), i);
  }

  @nonVirtual
  Future<void> nextTurn(GameContext<T> context) async {
    final i = getNextTurnIndex(context.turnIndex);
    _nextTurn(context, i);
  }

  Future<void> _nextTurn(GameContext<T> context, int i) async {
    await onTurn(GameContext<T>(turnIndex: i, previousTurnIndex: context.turnIndex, player: players[i]));
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
    return await _showCodeFromDetails(channel: context.channel, embedColor: await getColor(context.member), owner: context.user).to(null);
  }

  @nonVirtual
  Future<void> _showCodeFromDetails({required TextChannel channel, required DiscordColor embedColor, required User owner}) async {
    await channel.sendMessage(MessageBuilder(embeds: [
      EmbedBuilder(
        color: embedColor,
        title: "Join Game: $name",
        description: "$description\n\nUse `joingame $code` to join, or `startgame $code` to start.",
        fields: [
          EmbedFieldBuilder(name: "Code", value: code.toDiscordCodeString(), isInline: true),
          EmbedFieldBuilder(name: "Owner", value: owner.mention, isInline: true),
        ],
      ),
    ]));
  }

  @nonVirtual
  Future<void> end() async {
    ended = true;
    Logger.print("Games", "Game $name:$code ended");
  }

  @nonVirtual
  Future<String?> join(ChatContext context) async {
    if (players.length + 1 > maxPlayers) return "Maximum number of players reached.";

    final channel = await tryCatchA(() => context.client.users.createDm(context.user.id));
    if (channel == null) return "We couldn't send you a DM.";

    final message = await tryCatchA(() => channel.sendMessage(MessageBuilder(content: "Loading...")));
    if (message == null) return "We couldn't send you a message in your DMs.";

    if (players.length + 1 > maxPlayers) {
      await message.edit(MessageUpdateBuilder(content: "Maximum number of players reached."));
      return "Maximum number of players reached.";
    }

    players.add(newGameProfile(NewGameProfileDetails(user: context.user, channel: channel)));
    await message.edit(MessageUpdateBuilder(content: "Waiting for ${ownerPlayer.formattedDisplayName} to start the game!"));
    return null;
  }

  @nonVirtual
  FutureOr<void> updatePublicMessage(MessageUpdateBuilder builder) async {
    await publicMessage?.update(builder);
  }
}