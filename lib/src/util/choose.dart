import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

Map<String, String> indices = {
  "1": "1️⃣",
  "2": "2️⃣",
  "3": "3️⃣",
  "4": "4️⃣",
  "5": "5️⃣",
  "6": "6️⃣",
  "7": "7️⃣",
  "8": "8️⃣",
  "9": "9️⃣",

  "A": "🇦",
  "B": "🇧",
  "C": "🇨",
  "D": "🇩",
  "E": "🇪",
  "F": "🇫",
  "G": "🇬",
  "H": "🇭",
  "I": "🇮",
  "J": "🇯",
  "K": "🇰",
  "L": "🇱",
  "M": "🇲",
  "N": "🇳",
  "O": "🇴",
  "P": "🇵",
  "Q": "🇶",
  "R": "🇷",
  "S": "🇸",
  "T": "🇹",
  "U": "🇺",
  "V": "🇻",
  "W": "🇼",
  "X": "🇽",
  "Y": "🇾",
  "Z": "🇿",
};

class ChooseResult {
  final String? chosenId;
  final Message? sentMessage;

  const ChooseResult({required this.chosenId, required this.sentMessage});
}

/// [items] is a map of ID to human-readable option.
Future<ChooseResult> chooseFromList(ChatContext context, Map<String, String> items, {String prompt = "Pick from one of the below options.", Duration timeLimit = const Duration(minutes: 1), Message? message}) async {
  if (items.isEmpty) return ChooseResult(chosenId: null, sentMessage: null);
  if (items.length == 1) return ChooseResult(chosenId: items.keys.first, sentMessage: null);
  int secondsRemaining = timeLimit.inSeconds;

  Future<void> Function() onTimeUp = () async {
    Logger.warn("Confirmation", "Confirmation session with user ${context.user.id} has not set onTimeUp at this point. The confirmation will appear broken.");
  };

  final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
    secondsRemaining--;

    if (secondsRemaining <= 0) {
      Logger.print("Confirmation", "Confirmation session with user ${context.user.id} hit time limit.");
      onTimeUp.call();
      timer.cancel();
    }
  });

  try {
    message ??= await context.channel.sendMessage(MessageBuilder(content: "$prompt\n\n${items.values.mapIndexed((i, x) => "${i + 1}. $x").join("\n")}\n\nSend a number to pick an option, or `stop`/`cancel` to cancel.."));

    final controller = StreamController<MessageCreateEvent>();
    context.client.onMessageCreate.listen((x) => controller.isClosed ? null : controller.sink.add(x));

    onTimeUp = () async {
      await tryCatchA(() => message!.edit(MessageUpdateBuilder(content: "${message.content}\n-# This prompt has been ended.")));
      controller.close();
    };

    await for (final event in controller.stream) {
      if (event.message.channelId != context.channel.id) continue;
      if (event.message.author.id != context.user.id) continue;
      if (event.message.author is! User) continue;

      if (["stop", "cancel"].contains(event.message.content.trim().toLowerCase())) {
        await onTimeUp();
        return ChooseResult(chosenId: null, sentMessage: message);
      }

      final author = event.message.author as User;
      final result = int.tryParse(event.message.content);
      if (result == null) continue;

      final entry = items.entries.toList().elementAtOrNull(result - 1);
      if (entry == null) continue;

      await onTimeUp();
      return ChooseResult(chosenId: entry.key, sentMessage: message);
    }
  } catch (e) {
    Logger.warn("Choose", "Error: $e");
  }

  return ChooseResult(chosenId: null, sentMessage: null);
}

BotCommand _testChoose() => BotCommand("testchoose", "Debug", "Test choosing options.", (ChatContext context) async {
  final options = {"1": "Option 1", "2": "Option 2", "3": "Option 3"};
  final result = await chooseFromList(context, options);

  await context.respond(MessageBuilder(content: [
    "Chosen ID: ${result.chosenId.toDiscordCodeString()}",
    "Chosen option: ${options[result.chosenId ?? ""].toDiscordCodeString()}",
    "Message returned: ${result.sentMessage.runtimeType.toDiscordCodeString()}",
  ].join("\n")));
}, permissionsRequired: BotCommandPermissions.owner);

List<BotCommand> chooseDebug() => [
  _testChoose(),
  BotCommand("listchooseindices", "Debug", "List ${indices.length} indices.", (ChatContext context) async {
    await context.respond(MessageBuilder(content: indices.entries.mapIndexed((i, x) {
      return "$i. ${x.key}: ${x.value}";
    }).join("\n")));
  }),
  BotCommand("testpages", "Debug", "Test a page selection.", (ChatContext context, [GreedyString? start]) async {
    final completer = Completer<bool>();

    await Page("root", "Test", actions: [
      Action("smth", "Print something", onSelect: (details) async {
        await details.message.edit(MessageUpdateBuilder(content: "something"));
      }),
      Action("smthelse", "Print something else", onSelect: (details) async {
        await details.message.edit(MessageUpdateBuilder(content: "something else"));
      }),
      Page("morestuff", "More stuff", actions: [
        Action("smth1", "Print something 1", onSelect: (details) async {
          await details.message.edit(MessageUpdateBuilder(content: "something 1"));
        }),
        Action("smth2", "Print something 2", onSelect: (details) async {
          await details.message.edit(MessageUpdateBuilder(content: "something 2"));
        }),
      ]),
    ]).startHere(context, onCancel: (details) async {
      await details.message.edit(MessageUpdateBuilder(content: "Cancelled!"));
      completer.complete(false);
    }, startingPage: start?.data);

    final result = await completer.future;
  }),
];

class OnSelectDetails {
  final ChatContext context;
  final Message message;
  final Page? previousPage;
  final OnSelectDetails? previousDetails;
  final void Function(OnSelectDetails details) onCancel;

  OnSelectDetails({required this.context, required this.message, required this.previousPage, required this.onCancel, required this.previousDetails});

  @override
  String toString() {
    return "OnSelectDetails(context: $context, message: $message, previousPage: $previousPage, previousDetails: $previousDetails, onCancel: $onCancel)";
  }
}

abstract class Selection {
  final String id;
  final String name;
  final String? customEmoji;

  Selection(this.id, this.name, {this.customEmoji});

  FutureOr<void> _onSelect(OnSelectDetails details);
}

class Action extends Selection {
  final FutureOr<void> Function(OnSelectDetails details) onSelect;

  Action(super.id, super.name, {required this.onSelect, super.customEmoji});

  @override
  FutureOr<void> _onSelect(OnSelectDetails details) {
    return onSelect(details);
  }

  @override
  String toString() {
    return "Action(id: ${this.id}, name: $name, onSelect: $onSelect, customEmoji: $customEmoji)";
  }
}

class Page extends Selection {
  final List<Selection> actions;

  Page(super.id, super.name, {required this.actions}) : assert(actions.isNotEmpty, "Provide at least 1 action.");

  @override
  String toString() {
    return "Page(id: ${this.id}, name: $name, actions: $actions)";
  }

  @override
  Future<void> _onSelect(OnSelectDetails details) async {
    final allActions = [...actions, if (details.previousPage != null) Action("back", "*Back to*: **${details.previousPage?.name}**", onSelect: (_) => details.previousPage!._onSelect(details.previousDetails!)), Action("quit", "*Quit*", onSelect: (details) => details.onCancel(details), customEmoji: "⏹️")];

    final content = "## $name\n\n${allActions.mapIndexed((i, action) {
      final max = min(indices.length, maxUniqueReactionsPerMessage);
      if (i >= max) throw StateError("Too many options! Received ${actions.length}, but max is $max. Try splitting your actions up into pages.");

      final index = indices.entries.elementAt(i);
      final effect = action is Page ? "**" : "";
      return "${index.key}. $effect${action.name}$effect";
    }).join("\n")}";

    final idx = indices.entries.mapIndexed((i, x) => (id: x.key, emoji: x.value, index: i)).toList().sublist(0, allActions.length);
    await details.message.edit(MessageUpdateBuilder(content: content));
    await details.message.deleteAllReactions();

    () async {
      try {
        for (final i in idx) {
          final option = allActions.elementAtOrNull(i.index);
          await details.message.react(ReactionBuilder(id: null, name: option?.customEmoji ?? i.emoji));
        }
      } catch (e) {
        Logger.warn("Choose", "Unable to react: $e");
      }
    }();

    final controller = StreamController<MessageReactionAddEvent>();
    details.context.client.onMessageReactionAdd.listen((x) => controller.isClosed ? null : controller.sink.add(x));
    ({String emoji, String id, int index})? result;

    Future<void> Function() onTimeUp = () async {
      controller.close();
      details.onCancel(details);
    };

    await for (final event in controller.stream) {
      if (event.messageAuthorId == null || event.messageAuthorId != details.message.author.id || event.message.id != details.message.id || event.userId == details.context.client.user.id) continue;
      final emoji = event.emoji.name;

      final option = idx.firstWhereOrNull((x) => x.emoji == emoji);
      if (option == null) continue;

      result = option;
      break;
    }

    await details.message.deleteAllReactions();
    await details.message.edit(MessageUpdateBuilder(content: "Loading..."));

    if (result != null) {
      final option = allActions[result.index];
      option._onSelect(OnSelectDetails(context: details.context, message: details.message, previousPage: this, onCancel: details.onCancel, previousDetails: details));
    } else {
      details.onCancel(details);
    }
  }

  Future<void> startHere(ChatContext context, {Message? message, required void Function(OnSelectDetails details) onCancel, String? startingPage}) async {
    message ??= await context.respond(MessageBuilder(content: "Loading..."));
    final start = startingPage != null ? actions.firstWhereOrNull((x) => x is Page && (x.id == startingPage || x.name == startingPage)) as Page? : null;
    final details = OnSelectDetails(context: context, message: message, previousPage: null, previousDetails: null, onCancel: onCancel);

    if (start == null) {
      await _onSelect(details);
    } else {
      await start._onSelect(OnSelectDetails(context: context, message: message, previousPage: this, onCancel: onCancel, previousDetails: details));
    }
  }
}