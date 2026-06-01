import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

const decks = 2;
const rounds = 4;

final Map<int, String> cards = {
  1: "A",
  2: "2",
  3: "3",
  4: "4",
  5: "5",
  6: "6",
  7: "7",
  8: "8",
  9: "9",
  10: "10",
  11: "J",
  12: "Q",
  13: "K",
  14: "G",
};

final Map<int, List<int>> values = {
  1: [1, 11],
  2: [2],
  3: [3],
  4: [4],
  5: [5],
  6: [6],
  7: [7],
  8: [8],
  9: [9],
  10: [10],
  11: [10],
  12: [10],
  13: [10],
  14: [3, 5, 7, 9],
};

final Map<int, int> allCards = cards.keys.map((x) => List.filled(4 * decks, x)).flatten().toList().asMap();
final cardMap = cards;

int getCard(Map<int, int> cards) {
  final x = cards.entries.toList().ro();
  cards.remove(x.key);
  return x.value;
}

extension Ro<T> on List<T> {
  T ro() {
    return this[Random().nextInt(length)];
  }
}

List<int> getAllScores({bool includeOver = false, required List<int> cards}) {
  Set<int> results = {};

  void recurse(int index, int currentScore) {
    if (index == cards.length) {
      results.add(currentScore);
      return;
    }

    final cardValues = values[cards[index]] ?? [0];
    for (final v in cardValues) recurse(index + 1, currentScore + v);
  }

  recurse(0, 0);
  return results.where((x) => includeOver || x <= 21).toList()..sort((a, b) => b.compareTo(a));
}

class Dealer {
  List<int> cards = [];

  List<int> get possibleScores => getAllScores(cards: cards);
  int? get biggestPossibleScore => possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b);
}

class BlackjackProfile extends GameProfile {
  List<int> cards = [];
  int wins = 0;
  bool done = false;

  List<int> get possibleScores => getAllScores(cards: cards);
  int? get biggestPossibleScore => possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b);
  bool get blackjackIn2 => biggestPossibleScore == 21 && cards.length == 2;

  BlackjackProfile({required super.user, required super.channel});
}

class Blackjack extends MultiplayerGame<BlackjackProfile> {
  Blackjack({required super.client, required super.store, required super.owner, super.publicMessage}) : super(version: Version.parse("1.0.0A"));

  @override
  String get description => "Blackjack! Who can get the most wins in $rounds rounds?";

  final dealer = Dealer();
  final allCardsX = Map<int, int>.from(allCards);

  int round = 0;

  @override
  Future<int> getNextTurnIndex(int? i) async {
    if (i == null || i + 1 > players.length) return 0;
    i++;
    final x = i > players.length ? 0 : i;

    if (players.elementAtOrNull(x)?.done ?? false) {
      return getNextTurnIndex(x);
    } else {
      return x;
    }
  }

  @override
  int get minPlayers => 1;

  @override
  int get maxPlayers => 12;

  @override
  String get name => "Blackjack";

  @override
  BlackjackProfile newGameProfile(NewGameProfileDetails details) {
    return BlackjackProfile(user: details.user, channel: details.channel);
  }

  @override
  FutureOr<String?> onJoin(context) {
    if (this.started) return "This game has already been started.";
    return null;
  }

  @override
  FutureOr<void> onTurn(GameContext<BlackjackProfile> context) async {
    final player = context.player;
    player?.cards.add(getCard(allCardsX));

    await runForAllButCurrentPlayer(context, (player) async {
      await player.channel.sendMessage(MessageBuilder(content: context.player != null ? "# It's ${context.player?.formattedDisplayName}'s turn! (${context.turnIndex + 1}/${players.length})\nRound ${round + 1}/$rounds" : "Loading..."));
    });

    if (player == null) {
      dealer.cards.add(getCard(allCardsX));

      final scoreList = players.map((x) {
        return "- ${x.formattedDisplayName}: **${x.biggestPossibleScore ?? "Busted!"}**";
      }).join("\n");

      String getDealerMessage(String? action) {
        return "# It's the dealer's turn!\n\nDealer's cards: **${dealer.cards.map((x) => cardMap[x]).join(", ")}**\nDealer's possible scores: ${dealer.possibleScores.nullIfEmpty?.mapIndexed((i, x) => "${i == 0 || x == 21 ? "**" : ""}$x${i == 0 || x == 21 ? "**" : ""}").join(", ") ?? "**Busted!**"}${action != null ? "\n\n$action" : ""}\n\nScores:\n$scoreList";
      }

      final messages = await runForAllPlayers((profile) async {
        return await profile.channel.sendMessage(MessageBuilder(content: getDealerMessage(null)));
      });

      Future<void> update(String? action) async {
        await Future.wait(messages.map((message) async {
          await message.edit(MessageUpdateBuilder(content: getDealerMessage(action)));
        }));
      }

      await Future.delayed(Duration(seconds: 3));
      await update("The dealer will **hit**.");
      dealer.cards.add(getCard(allCardsX));

      while (true) {
        if (dealer.biggestPossibleScore == null) {
          await update("The dealer **busted**.");
          await Future.delayed(Duration(seconds: 5));
          break;
        }

        await Future.delayed(Duration(seconds: 3));
        await update(null);

        if (dealer.biggestPossibleScore! >= 17) {
          await update("The dealer will **pass**.");
          await Future.delayed(Duration(seconds: 5));
          break;
        }

        await Future.delayed(Duration(seconds: 3));
        await update("The dealer will **hit**.");
        await Future.delayed(Duration(seconds: 3));
        dealer.cards.add(getCard(allCardsX));
      }

      bool dealerBusted = dealer.possibleScores.isEmpty;

      List<BlackjackProfile> winners = players.where((player) {
        if (dealerBusted) return player.possibleScores.isNotEmpty;
        return player.biggestPossibleScore != null && player.biggestPossibleScore! > dealer.biggestPossibleScore!;
      }).toList();

      for (final winner in winners) {
        if (winner.blackjackIn2) {
          winner.wins += 2;
        } else {
          winner.wins += 1;
        }
      }

      await runForAllPlayers((player) async {
        player.done = false;

        await player.channel.sendMessage(MessageBuilder(content: "# Round ${round + 1}/$rounds is over!\nHere are the results!\n\n$scoreList\n- The dealer: **${dealer.possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b) ?? "Busted!"}**\n\nWinners:\n${winners.map((player) {
          return "- ${player.formattedDisplayName}: **+${player.blackjackIn2 ? 2 : 1}**";
        }).join("\n").nullIfEmptyTrimmed ?? "There were no winners!"}\n\nScoreboard:\n${players.sorted((a, b) => b.wins.compareTo(a.wins)).map((player) {
          return "- ${player.formattedDisplayName}: **${player.wins}**";
        }).join("\n")}\n\nContinuing in **10** seconds..."));
      });

      for (final p in players) {
        p.cards.clear();
        p.done = false;
      }

      dealer.cards.clear();
      round++;
      await Future.delayed(Duration(seconds: 10));

      if (round >= rounds) {
        final sorted = players.sorted((a, b) => b.wins.compareTo(a.wins));
        final winners = sorted.where((x) => x.wins >= sorted.first.wins);

        await runForAllPlayers((player) async {
          await player.channel.sendMessage(MessageBuilder(
            content: "# The game is over!\n\n${winners.length == 1 ? "The winner was:\n**${winners.first.formattedDisplayName}** with **${winners.first.wins}** points!" : "There were **${winners.length}** winners!\n${winners.map((player) {
              return "- ${player.formattedDisplayName}: **${player.wins}** points";
            })}"}\n\n${sorted.map((player) {
              return "- ${player.formattedDisplayName}: **${player.wins}** points";
            }).join("\n")}\n\nThanks for playing!",
          ));
        });

        return;
      }

      await nextTurn(context);
      return;
    }

    final myCards = context.player!.cards;

    Future<void> eval() async {
      Message message = await context.player!.channel.sendMessage(MessageBuilder(content: "Loading..."));

      String? getMessage() {
        final scores = getAllScores(cards: myCards);
        return "**It's your turn!**\n\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**\nYour possible scores: ${scores.mapIndexed((i, x) => "${i == 0 || x == 21 ? "**" : ""}$x${i == 0 || x == 21 ? "**" : ""}").join(", ")}\n\n:one:: Hit\n:two:: Pass";
      }

      final timeLimit = Duration(minutes: 1);
      int secondsRemaining = timeLimit.inSeconds;
      bool hit = false;

      Future<void> Function() onTimeUp = () async {
        Logger.warn("BJ", "BJ session with user ${player.user.id} has not set onTimeUp at this point. The confirmation will appear broken.");
      };

      final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
        secondsRemaining--;

        if (secondsRemaining <= 0) {
          Logger.print("BJ", "BJ session with user ${player.user.id} hit time limit.");
          onTimeUp.call();
          timer.cancel();
        }
      });

      await message.edit(MessageUpdateBuilder(content: getMessage()));
      await message.react(ReactionBuilder(name: "1️⃣", id: null));
      await message.react(ReactionBuilder(name: "2️⃣", id: null));

      try {
        final controller = StreamController<MessageReactionAddEvent>();
        client.onMessageReactionAdd.listen((x) => controller.isClosed ? null : controller.sink.add(x));

        onTimeUp = () async {
          countdown.cancel();
          controller.close();
        };

        await for (final event in controller.stream) {
          if (event.messageId != message.id)
          if (event.message.channelId != player.channel.id) continue;
          if (event.userId != context.player!.user.id) continue;

          hit = event.emoji.name == "1️⃣";
          break;
        }
      } catch (e) {
        Logger.warn("BJ", "Error: $e");
      }

      if (hit) {
        myCards.add(getCard(allCardsX));

        if (context.player?.biggestPossibleScore == null) {
          await context.player!.channel.sendMessage(MessageBuilder(content: "# You busted!\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**"));
          await nextTurn(context);
          return;
        } else {
          if (player.biggestPossibleScore == 21) {
            await context.player!.channel.sendMessage(MessageBuilder(content: "# You got a blackjack!\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**"));
            await nextTurn(context);
          } else {
            await message.delete();
            await eval();
            return;
          }
        }
      } else {
        await context.player!.channel.sendMessage(MessageBuilder(content: "Your score: **${context.player?.biggestPossibleScore}**\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**"));
        await nextTurn(context);
        return;
      }
    }

    await eval();
  }
}

class BlackjackPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "blackjack", version: Version.parse("1.0.0A"), description: "Commands for Blackjack.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      ...MultiplayerPlugin.gameCommands(name: "Blackjack", abbr: "bj", store: store, newGame: (context) => Blackjack(client: context.client, store: store, owner: context.user)),
    ];
  }
}