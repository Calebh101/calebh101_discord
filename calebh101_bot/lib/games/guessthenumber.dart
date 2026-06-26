import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';

const highest = 1_000_000;

class GTNEntry {
  final bool higher;
  final int number;

  const GTNEntry(this.number, this.higher);

  @override
  String toString() {
    return "- **${higher ? "Higher" : "Lower"}** than **$number**";
  }
}

extension on List<GTNEntry> {
  ({int low, int high}) get range {
    int low = where((x) => x.higher).nullIfEmpty?.reduce((a, b) => a.number > b.number ? a : b).number ?? 0;
    int high = where((x) => !x.higher).nullIfEmpty?.reduce((a, b) => a.number < b.number ? a : b).number ?? highest;
    return (low: low, high: high);
  }
}

class GuessTheNumber extends MultiplayerGame {
  final int number;

  GuessTheNumber({required super.client, required super.store, required super.owner, super.publicMessage}) : number = Random().nextInt(highest + 1), super(version: Version.parse("1.0.0A")) {
    Logger.print("GTN", "New GTN: owner=${owner.id}, number=$number");
  }

  @override
  String get name => "Guess the Number";

  @override
  String get description => "Guess the randomly generated number between 1-$highest (inclusive)!";

  @override
  int get minPlayers => 1;

  @override
  int? get maxPlayers => null;

  List<GTNEntry> hints = [];
  int turn = 0;

  @override
  int getNextTurnIndex(int? i) {
    if (i == null) return 0;
    i++;
    return i + 1 > players.length ? 0 : i;
  }

  @override
  FutureOr<String?> onJoin(_) => null;

  @override
  FutureOr<String?> onJoinBot() => null;

  @override
  Future<void> onTurn(GameContext context) async {
    final player = context.player;
    if (player == null) throw Exception();

    await runForAllButCurrentPlayer(context, (player) async {
      await player.channel?.sendMessage(MessageBuilder(embeds: [
        EmbedBuilder(
          description: "It's ${context.player?.formattedDisplayName}'s turn! (${context.turnIndex + 1}/${players.length})",
          color: Severity.blue.color,
        )
      ]));
    });

    await updatePublicMessage(MessageUpdateBuilder(content: "", embeds: [
      EmbedBuilder(
        title: "It's ${context.player?.formattedDisplayName}'s turn!",
        description: hints.join("\n"),
        color: await getColor(null),
        footer: EmbedFooterBuilder(text: "Turn ${turn + 1}"),
      ),
    ]));

    turn++;
    int? chosen;

    if (player.isBot) {
      final range = hints.range;
      final n = (range.high - range.low) / 2;

      chosen = n.ceil() + range.low;
      await Future.delayed(Duration(seconds: 3));
    } else {
      await player.channel?.sendMessage(MessageBuilder(embeds: [
        EmbedBuilder(
          description: "**It's your turn!**\n\nType your number of choice below. Reminder: The number is in between 1-$highest (inclusive).\nType `skip` to skip your turn.\nCurrent range: **${hints.range.low}-${hints.range.high}**\n\n${hints.join("\n")}".trim(),
          color: Severity.warning.color,
        ),
      ]));

      final timeLimit = Duration(minutes: 1);
      int secondsRemaining = timeLimit.inSeconds;

      Future<void> Function() onTimeUp = () async {
        Logger.warn("GTN", "GTN session with user ${player.id} has not set onTimeUp at this point. The confirmation will appear broken.");
      };

      final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
        secondsRemaining--;

        if (secondsRemaining <= 0) {
          Logger.print("GTN", "GTN session with user ${player.id} hit time limit.");
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
          if (event.message.channelId != player.channel?.id) continue;
          if (event.message.author.id != player.user?.id) continue;
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
        await runForAllPlayers((player) async {
          await player.channel?.sendMessage(MessageBuilder(content: "${context.player?.formattedDisplayName} skipped."));
        });

        await Future.delayed(Duration(seconds: 5));
        await nextTurn(context);
        return;
      }
    }

    if (chosen == number) {
      await runForAllPlayers((player) async {
        await player.channel?.sendMessage(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "**${context.player?.formattedDisplayName} won!**\n\n${context.player?.formattedDisplayName} guessed the number correctly, which was **$number**.",
            color: Severity.good.color,
          ),
        ]));
      });

      await end();

      await updatePublicMessage(MessageUpdateBuilder(embeds: [
        EmbedBuilder(
          title: "${context.player?.formattedDisplayName} won!",
          description: "# $number\n\n${hints.join("\n")}",
          color: await getColor(null),
          footer: EmbedFooterBuilder(text: "Turn ${turn + 1}"),
        ),
      ]));

      return;
    }

    await runForAllPlayers((player) async {
      await player.channel?.sendMessage(MessageBuilder(embeds: [
        EmbedBuilder(
          description: "${context.player?.formattedDisplayName} guessed **$chosen** and was wrong. The actual number is **${number > chosen! ? "higher" : "lower"}**.",
          color: Severity.severe.color,
        ),
      ]));
    });

    hints.add(GTNEntry(chosen, number > chosen));
    await Future.delayed(Duration(seconds: 5));
    await nextTurn(context);
  }

  @override
  GameProfile newGameProfile(NewGameProfileDetails details) {
    return GameProfile(details: details.details);
  }
}

class GuessTheNumberPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "guessthenumber", version: Version.parse("1.0.0A"), description: "Commands for Guess the Number.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("newgtn", "Games", "New Guess the Number game!", (T context) async {
        await newGame(context, store: store, newGame: () => GuessTheNumber(client: context.client, store: store, owner: context.user));
      }),
    ];
  }

  @override
  FutureOr<void> onRegister() {
    registerGame(GameData(
      "Guess the Number",
      minPlayers: 1, maxPlayers: 8,
      description: "In this game, you're working together with everyone else to try to guess a number between **1-$highest** (inclusive). Each time you guess, you'll get told if the *actual* number is **higher** or **lower** than your guess.",
    ));
  }
}