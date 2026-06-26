import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

const decks = 2;

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
};

final Map<int, int> allCards = cards.keys.map((x) => List.filled(4 * decks, x)).flatten().toList().asMap();
final cardMap = cards;

bool isSoft17(List<int> cards) {
  if (!cards.contains(1)) return false;
  final scores = getAllScores(cards: cards, includeOver: true);
  return scores.contains(17) && scores.any((s) => s < 17);
}

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
  Message? notYourTurnMessage;
  num? bet;
  num gained = 0;

  List<int> get possibleScores => getAllScores(cards: cards);
  int? get biggestPossibleScore => possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b);
  bool get blackjackIn2 => biggestPossibleScore == 21 && cards.length == 2;

  BlackjackProfile({required super.details});

  bool won(Dealer dealer) {
    final busted = dealer.possibleScores.isEmpty;
    if (busted) return possibleScores.isNotEmpty;
    return biggestPossibleScore != null && biggestPossibleScore! > dealer.biggestPossibleScore!;
  }
}

abstract class BlackjackBettingPlugin<T extends num> {
  BlackjackBettingPlugin();

  void add(User user, T input);
  T get(User user);
  String getName(T amount);

  T get lowBet;
  T get highBet;
}

abstract class Blackjack extends MultiplayerGame<BlackjackProfile> {
  final int rounds;
  final BlackjackBettingPlugin? betting;

  Blackjack({required super.client, required super.store, required super.owner, super.publicMessage, required this.rounds, this.betting}) : super(version: Version.parse("1.0.0A"));

  @override
  String get description => "Blackjack! Who can get the most wins in $rounds rounds?";

  final dealer = Dealer();
  var allCardsX = Map<int, int>.from(allCards);
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
  int? get maxPlayers => 12;

  @override
  String get name => "Blackjack";

  @override
  BlackjackProfile newGameProfile(NewGameProfileDetails details) {
    return BlackjackProfile(details: details.details);
  }

  @override
  FutureOr<String?> onJoin(context) {
    if (this.started) return "This game has already been started.";
    Logger.print("BJ", "Checking user ${context.user.id}: betting=${betting.runtimeType}, amount=${betting?.get(context.user)}, needed=${betting?.lowBet}*$rounds");

    if (betting != null) {
      final amount = betting!.get(context.user);
      final needed = betting!.lowBet * rounds;

      if (amount < needed) {
        return "You don't have enough ${betting?.getName(amount)}! You need **$needed** (for all **$rounds** rounds).";
      }
    }

    return null;
  }

  @override
  FutureOr<String?> onJoinBot() {
    if (this.started) return "This game has already been started.";
    if (betting != null) return "Bots can't be added to Blackjack games when betting is allowed, as bots don't have ${betting?.getName(0)}.";
    return null;
  }

  @override
  FutureOr<void> onTurn(GameContext<BlackjackProfile> context) async {
    final player = context.player;
    player?.cards.add(getCard(allCardsX));

    Future<void> updateNotYourTurn() async {
      await runForAllButCurrentPlayer(context, (player) async {
        player.notYourTurnMessage ??= await player.channel?.sendMessage(MessageBuilder(content: "Loading..."));
        final length = context.player?.cards.length;

        await player.notYourTurnMessage?.edit(MessageUpdateBuilder(content: "", embeds: [
          EmbedBuilder(
            description: context.player != null ? "# It's ${context.player?.formattedDisplayName}'s turn! (${context.turnIndex + 1}/${players.length})\n${betting != null && context.player?.bet == null ? "They're currently placing their bets!" : "They have **$length** ${Word.fromCount(length ?? 0, singular: Word("card"))}."}\nRound ${round + 1}/$rounds" : "Loading...",
            color: Severity.purple.color,
          )
        ]));
      });
    }

    final scoreboard = players.sorted((a, b) => b.wins.compareTo(a.wins)).map((player) {
      return "- ${player.formattedDisplayName}: **${player.wins}**";
    }).join("\n");

    if (player == null) {
      dealer.cards.add(getCard(allCardsX));

      final scoreList = players.map((x) {
        return "- ${x.formattedDisplayName}: **${x.biggestPossibleScore ?? "Busted!"}**";
      }).join("\n");

      Future<void> pm() async {
        await updatePublicMessage(MessageUpdateBuilder(embeds: [
          EmbedBuilder(
            title: "It's the dealer's turn!",
            fields: [
              EmbedFieldBuilder(name: "Cards", value: "**${dealer.cards.map((x) => cardMap[x]).join(", ")}**\n= ${dealer.possibleScores.nullIfEmpty?.mapIndexed((i, x) => "${i == 0 || x == 21 ? "**" : ""}$x${i == 0 || x == 21 ? "**" : ""}").join(", ") ?? "**Busted!**"}", isInline: false),
              EmbedFieldBuilder(name: "Scores", value: scoreList, isInline: false),
              EmbedFieldBuilder(name: "Scoreboard", value: scoreboard, isInline: false),
            ],
            footer: EmbedFooterBuilder(text: "Round ${round + 1}/$rounds"),
            color: primaryBotColor,
          ),
        ]));
      }

      await pm();

      String getDealerMessage(String? action) {
        return "# It's the dealer's turn!\n\nDealer's cards: **${dealer.cards.map((x) => cardMap[x]).join(", ")}**\nDealer's possible scores: ${dealer.possibleScores.nullIfEmpty?.mapIndexed((i, x) => "${i == 0 || x == 21 ? "**" : ""}$x${i == 0 || x == 21 ? "**" : ""}").join(", ") ?? "**Busted!**"}${action != null ? "\n\n$action" : ""}\n\nScores:\n$scoreList";
      }

      final messages = await runForAllPlayers((profile) async {
        return await profile.channel?.sendMessage(MessageBuilder(embeds: [
          EmbedBuilder(
            description: getDealerMessage(null),
            color: Severity.blue.color,
          ),
        ]));
      });

      Future<void> update(String? action) async {
        await Future.wait(messages.map((message) async {
          await message?.edit(MessageUpdateBuilder(embeds: [
            EmbedBuilder(
              description: getDealerMessage(null),
              color: Severity.blue.color,
            ),
          ]));
        }));
      }

      await Future.delayed(Duration(seconds: 3));
      await update("The dealer will **hit**.");
      dealer.cards.add(getCard(allCardsX));

      while (true) {
        await pm();

        if (dealer.biggestPossibleScore == null) {
          await update("The dealer **busted**.");
          await Future.delayed(Duration(seconds: 5));
          break;
        }

        await Future.delayed(Duration(seconds: 3));
        await update(null);

        if (dealer.biggestPossibleScore! >= 17 && !isSoft17(dealer.cards)) {
          await update("The dealer will **pass**.");
          await Future.delayed(Duration(seconds: 5));
          break;
        }

        await Future.delayed(Duration(seconds: 3));
        await update("The dealer will **hit**.");
        await Future.delayed(Duration(seconds: 3));

        dealer.cards.add(getCard(allCardsX));
      }

      await pm();
      List<BlackjackProfile> winners = players.where((p) => p.won(dealer)).toList();

      for (final winner in winners) {
        if (winner.blackjackIn2) {
          winner.wins += 2;
        } else {
          winner.wins += 1;
        }
      }

      final winnersList = winners.map((player) {
        final gained = player.bet != null ? player.bet! * (player.blackjackIn2 ? 3 : 2) : null;
        return "- ${player.formattedDisplayName}: **+${player.blackjackIn2 ? 2 : 1}**";
      }).join("\n").nullIfEmptyTrimmed ?? "There were no winners!";

      final scoreboardX = players.sorted((a, b) => b.wins.compareTo(a.wins)).map((player) {
        return "- ${player.formattedDisplayName}: **${player.wins}**";
      }).join("\n");

      await runForAllPlayers((player) async {
        player.done = false;

        await player.channel?.sendMessage(MessageBuilder(
          embeds: [
            EmbedBuilder(
              description: "# Round ${round + 1}/$rounds is over!\nHere are the results!\n\n$scoreList\n- The dealer: **${dealer.possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b) ?? "Busted!"}**\n\nWinners:\n$winnersList\n\nScoreboard:\n$scoreboardX\n\nContinuing in **10** seconds...",
              color: Severity.good.color,
            ),
          ],
        ));
      });

      await updatePublicMessage(MessageUpdateBuilder(embeds: [
        EmbedBuilder(
          title: "Round ${round + 1}/$rounds is over!",
          fields: [
            EmbedFieldBuilder(name: "Scores", value: "$scoreList\n- The dealer: **${dealer.possibleScores.nullIfEmpty?.reduce((a, b) => a > b ? a : b) ?? "Busted!"}**", isInline: false),
            if (winners.isNotEmpty) EmbedFieldBuilder(name: "Winners", value: winnersList, isInline: false),
            EmbedFieldBuilder(name: "Scoreboard", value: scoreboardX, isInline: false),
          ],
          color: primaryBotColor,
          footer: EmbedFooterBuilder(text: "Round ${round + 1}/$rounds"),
        ),
      ]));

      for (final p in players) {
        if (p.isUser && p.bet != null && betting != null) {
          final bet = p.bet!;

          if (p.won(dealer)) {
            final gained = bet * (p.blackjackIn2 ? 3 : 2);
            betting!.add(p.user!, gained);
            p.gained += gained - bet;
          } else {
            p.gained -= bet;
          }
        }

        p.cards.clear();
        p.done = false;
        p.bet = null;
      }

      dealer.cards.clear();
      allCardsX = Map<int, int>.from(allCards);
      round++;
      await Future.delayed(Duration(seconds: 10));

      if (round >= rounds) {
        final sorted = players.sorted((a, b) => b.wins.compareTo(a.wins));
        final winners = sorted.where((x) => x.wins >= sorted.first.wins);

        final winnersListX = winners.length == 1 ? "The winner was:\n**${winners.first.formattedDisplayName}** with **${winners.first.wins}** points!" : "There were **${winners.length}** winners!\n${winners.map((player) {
          return "- ${player.formattedDisplayName}: **${player.wins}** points";
        }).join("\n")}";

        final scoreListX = sorted.map((player) {
          return "- ${player.formattedDisplayName}: **${player.wins}** points${betting != null ? () {
            final gained = player.gained;
            return " (**${gained >= 0 ? "+" : "-"}${gained.abs()}** ${betting?.getName(gained)})";
          }() : ""}";
        }).join("\n");

        await runForAllPlayers((player) async {
          await player.channel?.sendMessage(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "# The game is over!\n\n$winnersListX\n\n$scoreListX\n\nThanks for playing!",
              color: Severity.good.color,
            )
          ]));
        });

        await updatePublicMessage(MessageUpdateBuilder(embeds: [
          EmbedBuilder(
            title: "The game is over!",
            fields: [
              if (winners.isNotEmpty) EmbedFieldBuilder(name: "Winners", value: winnersListX, isInline: false),
              EmbedFieldBuilder(name: "Scoreboard", value: scoreListX, isInline: false),
            ],
            color: primaryBotColor,
            footer: EmbedFooterBuilder(text: "Round $round/$rounds"),
          ),
        ]));

        await end();
        return;
      }

      await nextTurn(context);
      return;
    }

    final myCards = context.player!.cards;

    await updatePublicMessage(MessageUpdateBuilder(content: "", embeds: [
      EmbedBuilder(
        title: "It's ${player.formattedDisplayName}'s turn! (${context.turnIndex + 1}/${players.length})",
        fields: [
          EmbedFieldBuilder(name: "Scoreboard", value: scoreboard, isInline: false),
        ],
        footer: EmbedFooterBuilder(text: "Round ${round + 1}/$rounds"),
        color: primaryBotColor,
      ),
    ]));

    Future<void> eval() async {
      final isBetting = betting != null && player.bet == null;
      await updateNotYourTurn();

      Message? message = await context.player!.channel?.sendMessage(MessageBuilder(content: "Loading..."));
      bool hit = false;

      if (context.player!.isUser) {

        String? getMessage() {
          final scores = getAllScores(cards: myCards);
          return "# It's your turn!\nRound ${round + 1}/$rounds\n\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**\nYour possible scores: ${scores.mapIndexed((i, x) => "${i == 0 || x == 21 ? "**" : ""}$x${i == 0 || x == 21 ? "**" : ""}").join(", ")}\n\n:one:: Hit\n:two:: Pass";
        }

        final timeLimit = Duration(minutes: 1);
        int secondsRemaining = timeLimit.inSeconds;

        Future<void> Function() onTimeUp = () async {
          Logger.warn("BJ", "BJ session with user ${player.id} has not set onTimeUp at this point. The confirmation will appear broken.");
        };

        final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
          secondsRemaining--;

          if (secondsRemaining <= 0) {
            Logger.print("BJ", "BJ session with user ${player.id} hit time limit.");
            onTimeUp.call();
            timer.cancel();
          }
        });

        bool availableForHighBet() {
          if (betting == null) return false;
          final roundsLeft = rounds - (round + 1);
          return betting!.get(player.user!) >= betting!.highBet * roundsLeft;
        }

        await message?.edit(MessageUpdateBuilder(content: "", embeds: [
          EmbedBuilder(
            description: isBetting ? "Select how much you will bet.\nYou have **${betting?.get(player.user!)}** ${betting?.getName(betting?.get(player.user!) ?? 0)}.\nYour first card: **${cards[myCards.firstOrNull]}**\n\n1️⃣ **${betting?.lowBet}** ${betting?.getName(betting!.lowBet)}\n2️⃣ **${betting?.highBet}** ${betting?.getName(betting!.highBet)} (**${availableForHighBet() ? "available" : "unavailable"}**)" : getMessage(),
            color: Severity.warning.color,
          ),
        ]));

        await message?.react(ReactionBuilder(name: "1️⃣", id: null));
        if (!isBetting || availableForHighBet()) await message?.react(ReactionBuilder(name: "2️⃣", id: null));

        try {
          final controller = StreamController<MessageReactionAddEvent>();
          client.onMessageReactionAdd.listen((x) => controller.isClosed ? null : controller.sink.add(x));

          onTimeUp = () async {
            countdown.cancel();
            controller.close();
          };

          await for (final event in controller.stream) {
            if (event.messageId != message?.id) continue;
            if (event.message.channelId != player.channel?.id) continue;
            if (event.userId != context.player!.id) continue;

            hit = event.emoji.name == "1️⃣"; // in betting, means low bet
            break;
          }
        } catch (e) {
          Logger.warn("BJ", "Error: $e");
        }

        countdown.cancel();

        if (isBetting) {
          final bet = !hit && availableForHighBet() ? betting!.highBet : betting!.lowBet;
          betting?.add(player.user!, bet);
          context.player!.bet = bet;

          await context.player!.channel?.sendMessage(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "# You Bet:\n**$bet** ${betting?.getName(bet)}",
              color: Severity.blue.color,
            ),
          ]));

          await eval();
          return;
        }
      } else {
        final personality = (player.details as BotPlayerDetails).personality;

        hit = (player.biggestPossibleScore ?? 0) < switch (personality) {
          .safe => 14,
          .average => 16,
          .risky => 18,
        };

        await Future.delayed(Duration(seconds: 3));
      }

      if (hit) {
        myCards.add(getCard(allCardsX));

        if (context.player?.biggestPossibleScore == null) {
          await context.player!.channel?.sendMessage(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "# You busted!\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**",
              color: Severity.severe.color,
            ),
          ]));

          return;
        } else {
          if (player.biggestPossibleScore == 21) {
            await context.player!.channel?.sendMessage(MessageBuilder(embeds: [
              EmbedBuilder(
                description: "# You got a blackjack!\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**",
                color: Severity.good.color,
              ),
            ]));

            return;
          } else {
            await message?.delete();
            await eval();
            return;
          }
        }
      } else {
        await context.player!.channel?.sendMessage(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "Your score: **${context.player?.biggestPossibleScore}**\nYour cards: **${myCards.map((x) => cards[x]).join(", ")}**",
            color: Severity.warning.color,
          )
        ]));
        return;
      }
    }

    await eval();
    for (final x in players) x.notYourTurnMessage = null;
    await nextTurn(context);
  }
}

abstract class BlackjackPlugin<T extends Blackjack> extends BotPlugin {
  @override get info => BotPluginInfo(id: "blackjack", version: Version.parse("1.0.0A"), description: "Commands for Blackjack.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<C extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand(newCommand, "Games", "New Blackjack game!", (C context, [int rounds = 4]) async {
        if (rounds < 1) return context.respondWithError("There must be more than 1 round.");
        if (rounds > 20) return context.respondWithError("You can't have more than 20 rounds.");

        await newGame(context, store: store, newGame: () => newBj(client: context.client, store: store, owner: context.user, rounds: rounds));
      }),
    ];
  }

  T newBj({required NyxxGateway client, required KVStore store, required User owner, required int rounds});
  String get newCommand => "newbj";

  @override
  FutureOr<void> onRegister() {
    registerGame(GameData(
      "Blackjack",
      minPlayers: 1, maxPlayers: 12,
      description: "Blackjack is a game where you're always trying to beat the dealer. You start out with 1 card, and you can either continue getting more (\"hitting\"), or you can pass and keep your cards. You're trying to get as close as you can to 21, without going over. If you go over, you get nothing\n\nThe dealer will go after each player, and will continue hitting until they get 17 or above.\n\nA couple special rules:\n- Tie goes to the dealer.\n- Aces count as either 1 or 11.\n- You can get double your bet if you get a blackjack in only 2 cards (an ace and a 10-king).\n\nCards:\n- 2-10\n- J: Jack\n- Q: Queen\n- K: King\n- A: Ace",
    ));
  }
}

class DefaultBlackjack extends Blackjack {
  DefaultBlackjack({required super.client, required super.store, required super.owner, required super.rounds});
}

class DefaultBlackjackPlugin extends BlackjackPlugin<DefaultBlackjack> {
  @override
  DefaultBlackjack newBj({required NyxxGateway client, required KVStore store, required User owner, required int rounds}) {
    return DefaultBlackjack(client: client, store: store, owner: owner, rounds: rounds);
  }
}