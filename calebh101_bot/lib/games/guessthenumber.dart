import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';

class GuessTheNumber extends MultiplayerGame {
  final int number;

  GuessTheNumber({required super.client, required super.store, required super.owner}) : number = Random().nextInt(50), super(version: Version.parse("1.0.0A"));

  @override
  String get name => "Guess the Number";

  @override
  String get description => "Guess the randomly generated number!";

  @override
  int get minPlayers => 2;

  @override
  int get maxPlayers => 8;

  @override
  int getNextTurnIndex(int i) {
    return i + 1 > players.length ? 0 : i;
  }

  @override
  FutureOr<String?> onJoin() => null;

  @override
  Future<void> onTurn(GameContext context) async {
    await updateAllButCurrentPlayer(context, MessageUpdateBuilder(content: "It's ${context.player.formattedDisplayName}'s turn! (${context.turnIndex + 1}/${players.length})"));
    await updatePlayer(context.player, MessageUpdateBuilder(content: "**It's your turn!**\n\nType your number of choice below. Reminder: The number is in between 1-100 (inclusive).\nType `skip` to skip your turn."));

    final timeLimit = Duration(minutes: 1);
    int secondsRemaining = timeLimit.inSeconds;
    int? chosen;

    Future<void> Function() onTimeUp = () async {
      Logger.warn("Confirmation", "Confirmation session with user ${context.player.user.id} has not set onTimeUp at this point. The confirmation will appear broken.");
    };

    final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
      secondsRemaining--;

      if (secondsRemaining <= 0) {
        Logger.print("Confirmation", "Confirmation session with user ${context.player.user.id} hit time limit.");
        onTimeUp.call();
        timer.cancel();
      }
    });

    try {
      final controller = StreamController<MessageCreateEvent>();
      client.onMessageCreate.listen((x) => controller.isClosed ? null : controller.sink.add(x));

      onTimeUp = () async {
        countdown.cancel();
        controller.close();
      };

      await for (final event in controller.stream) {
        if (event.message.channelId != context.player.message.channel.id) continue;
        if (event.message.author.id != context.player.user.id) continue;
        if (event.message.author is! User) continue;

        if (["skip"].contains(event.message.content.trim().toLowerCase())) {
          await onTimeUp();
          break;
        }

        final result = int.tryParse(event.message.content);
        if (result == null) continue;
        chosen = result;

        await onTimeUp();
        break;
      }
    } catch (e) {
      Logger.warn("GTN", "Error: $e");
    }

    if (chosen == null) {
      await updateAll(context, MessageUpdateBuilder(content: "${context.player.formattedDisplayName} skipped."));
      await Future.delayed(Duration(seconds: 5));
      await nextTurn(context);
    }

    if (chosen == number) {
      await updateAll(context, MessageUpdateBuilder(content: "**${context.player.formattedDisplayName} won!**\n\n${context.player.formattedDisplayName} guessed the number correctly, which was **$number**."));
      end();
      return;
    }

    await updateAll(context, MessageUpdateBuilder(content: "${context.player.formattedDisplayName} guessed **$chosen** and was wrong. The actual number is **${number > chosen! ? "higher" : "lower"}**."));
    await Future.delayed(Duration(seconds: 5));
    await nextTurn(context);
  }

  @override
  GameProfile newGameProfile(NewGameProfileDetails details) {
    return GameProfile(user: details.user, message: details.message);
  }
}