import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

abstract class MultiplayerGame extends CommandRegisterable {
  MultiplayerGame();

  int get minPlayers;
  int get maxPlayers;

  FutureOr<void> play({required List<User> players});
}