import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class ChooseResult {
  final String? chosenId;
  final Message? sentMessage;

  const ChooseResult({required this.chosenId, required this.sentMessage});
}

/// [items] is a map of ID to human-readable option.
Future<ChooseResult> chooseFromList(ChatContext context, Map<String, String> items, {String prompt = "Pick from one of the below options.", Duration timeLimit = const Duration(minutes: 1)}) async {
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
    final message = await context.channel.sendMessage(MessageBuilder(content: "$prompt\n\n${items.values.mapIndexed((i, x) => "${i + 1}. $x").join("\n")}\n\nSend a number to pick an option, or `stop`/`cancel` to cancel.."));

    final controller = StreamController<MessageCreateEvent>();
    context.client.onMessageCreate.listen((x) => controller.isClosed ? null : controller.sink.add(x));

    onTimeUp = () async {
      await tryCatchA(() => message.edit(MessageUpdateBuilder(content: "${message.content}\n-# This prompt has been ended.")));
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

BotCommand testChoose() => BotCommand("testchoose", "Debug", "Test choosing options.", (ChatContext context) async {
  final options = {"1": "Option 1", "2": "Option 2", "3": "Option 3"};
  final result = await chooseFromList(context, options);

  await context.respond(MessageBuilder(content: [
    "Chosen ID: ${result.chosenId.toDiscordCodeString()}",
    "Chosen option: ${options[result.chosenId ?? ""].toDiscordCodeString()}",
    "Message returned: ${result.sentMessage.runtimeType.toDiscordCodeString()}",
  ].join("\n")));
}, permissionsRequired: BotCommandPermissions.owner);