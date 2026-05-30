import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

abstract class MultiplayerGame extends CommandRegisterable {
  MultiplayerGame({required this.players});

  final List<User> players;

  int get minPlayers;
  int get maxPlayers;

  BotCommandPermissions get requiredPermsToStart => BotCommandPermissions.any;

  /// This is called when a player tries to join, whether on the starting screen or mid-round.
  ///
  /// If the user is not allowed to join, return a non-null `String` as the message that is returned.
  FutureOr<String?> onJoin();

  FutureOr<void> onStart();
}