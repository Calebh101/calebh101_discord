import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

class GameProfile {
  final User user;
  final Message message;

  GameProfile({required this.user, required this.message});

  String get formattedDisplayName => "*${user.globalName ?? user.username}*";
}

class GameContext<T extends GameProfile> {
  final T player;
  final int turnIndex;
  final int previousTurnIndex;

  GameContext<T> from({
    int? turnIndex,
    int? previousTurnIndex,
    T? player,
  }) {
    return GameContext<T>(
      turnIndex: turnIndex ?? this.turnIndex,
      previousTurnIndex: previousTurnIndex ?? this.previousTurnIndex,
      player: player ?? this.player,
    );
  }

  const GameContext({required this.turnIndex, required this.previousTurnIndex, required this.player});
}

class NewGameProfileDetails {
  final User user;
  final Message message;

  const NewGameProfileDetails({required this.user, required this.message});
}

abstract class MultiplayerGame<T extends GameProfile> extends BotPlugin {
  final User owner;
  final KVStore store;
  final NyxxGateway client;
  final String code;

  @override
  final Version version;

  MultiplayerGame({required this.client, required this.store, required this.owner, required this.version}) : code = List.generate(4, (i) => 'abcdefghijklmnopqrstuvwxyz'[Random().nextInt(4)]).join("");

  @override
  BotPluginInfo get info => BotPluginInfo(id: "game-${name.toLowerCase().replaceAll(" ", "-")}", version: version, description: description);

  List<T> players = [];
  Message? inviteMessage;
  bool ended = false;

  int get minPlayers;
  int get maxPlayers;

  String get name;
  String get description;

  BotCommandPermissions get requiredPermsToStart => BotCommandPermissions.any;

  int getNextTurnIndex(int currentIndex);

  T newGameProfile(NewGameProfileDetails details);

  /// This is called when a player tries to join, whether on the starting screen or mid-round.
  ///
  /// If the user is not allowed to join, return a non-null `String` as the message that is returned.
  FutureOr<String?> onJoin();

  FutureOr<void> onTurn(GameContext<T> context);

  @nonVirtual
  Future<void> nextTurn(GameContext<T> context) async {
    await Future.wait(players.map((x) => x.message.edit(MessageUpdateBuilder(content: "Loading..."))).whereType<Future>());
    await onTurn(context.from(turnIndex: getNextTurnIndex(context.turnIndex), previousTurnIndex: context.turnIndex));
  }

  @nonVirtual
  Future<void> updateAllButCurrentPlayer(GameContext<T> context, MessageUpdateBuilder builder) {
    return Future.wait(players.whereIndexed((i, x) => i != context.turnIndex).map((x) => x.message.edit(builder)).whereType<Future>());
  }

  @nonVirtual
  Future<void> updateAll(GameContext<T> context, MessageUpdateBuilder builder) {
    return Future.wait(players.map((x) => x.message.edit(builder)).whereType<Future>());
  }

  @nonVirtual
  Future<void> updatePlayer(T player, MessageUpdateBuilder builder) async {
    await player.message.edit(builder);
  }

  @nonVirtual
  Future<String?> showCode(ChatContext context) async {
    if (context.verifyPerms(requiredPermsToStart, ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id))) == false) return "You don't have permission to start this game!\n-# Required perms: `${requiredPermsToStart.name}`";
    return await _showCodeFromDetails(channel: context.channel, embedColor: await getColor(context.member), owner: context.user).to(null);
  }

  @nonVirtual
  Future<void> _showCodeFromDetails({required TextChannel channel, required DiscordColor embedColor, required User owner}) async {
    await channel.sendMessage(MessageBuilder(embeds: [
      EmbedBuilder(
        color: embedColor,
        title: "Join Game: $name",
        description: "$description\n\nUse `join $code` to join.",
        fields: [
          EmbedFieldBuilder(name: "Code", value: code.toDiscordCodeString(), isInline: true),
          EmbedFieldBuilder(name: "Owner", value: owner.mention, isInline: true),
        ],
      ),
    ]));
  }

  @nonVirtual
  void end() {
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

    players.add(newGameProfile(NewGameProfileDetails(user: context.user, message: message)));
    return null;
  }
}