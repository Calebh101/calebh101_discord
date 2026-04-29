import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';

class ConfirmationDetails {
  final String action;
  final bool? result;
  final String? error;

  const ConfirmationDetails({required this.action, required this.result, this.error});

  EmbedBuilder toEmbed({List<EmbedFieldBuilder>? fields}) {
    return EmbedBuilder(
      title: "Action ${result == true ? "Succeeded" : (result == false ? "Cancelled" : "Error")}!",
      description: action.toDiscordCodeBlock(),
      fields: [
        ...?fields,
        if (error != null) EmbedFieldBuilder(name: "Error", value: error!, isInline: false),
      ],
      color: DiscordColor.parseHexString(result == true ? "#90EE90" : "#FF7F7F"),
      timestamp: DateTime.now().toUtc(),
    );
  }
}

Future<ConfirmationDetails> confirmation(String action, ChatContext context, {User? user, bool deleteOriginalOnReturn = true, bool inDms = false, bool useCode = true, Duration timeLimit = const Duration(seconds: 30)}) async {
  user ??= context.user;
  late TextChannel channel;
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
    channel = inDms ? await context.client.users.createDm(user.id) : context.channel;
  } catch (e) {
    Logger.warn("Confirmation", "Unable to open channel: $e");
    countdown.cancel();
    return ConfirmationDetails(action: action, result: null, error: inDms ? "We couldn't DM you." : "We couldn't find a text channel.");
  }

  try {
    final n = Random().nextInt(9999 - 1111) + 1111;

    final m = await channel.sendMessage(MessageBuilder(embeds: [
      EmbedBuilder(
        title: "Confirmation",
        description: "${user.toMention()} needs to confirm action:\n${action.toDiscordCodeBlock()}\n${useCode ? "**To confirm, enter the following code:**\n### $n" : "**To confirm, send `y`.**"}",
        timestamp: DateTime.now().toUtc(),
        color: await getColor(await userToMember(user, guild: context.guild)),
      ),
    ], content: user.toMention()));

    final controller = StreamController<MessageCreateEvent>();
    context.client.onMessageCreate.listen((x) => controller.isClosed ? null : controller.sink.add(x));

    onTimeUp = () async {
      controller.close();
    };

    await for (final event in controller.stream) {
      if (event.message.channelId != channel.id) continue;
      if (event.message.author.id != user.id) continue;
      if (event.message.author is! User) continue;

      final author = event.message.author as User;
      final result = useCode ? (int.tryParse(event.message.content) == n) : (event.message.content.trim().toLowerCase() == "y");

      countdown.cancel();
      if (deleteOriginalOnReturn) await tryCatchA(() => m.delete());
      return ConfirmationDetails(action: action, result: result);
    }

    if (deleteOriginalOnReturn) await tryCatchA(() => m.delete());
    return ConfirmationDetails(action: action, result: false);
  } catch (e) {
    Logger.warn("Confirmation", "Unable to send message: $e");
    countdown.cancel();
    return ConfirmationDetails(action: action, result: null, error: "Unable to create confirmation dialog.\n\n\n${e.runtimeType}");
  }
}

BotCommand? confirmationTest() => dev ? BotCommand("confirmationtest", "Debug", "Test confirmation.", (ChatContext context, [bool dms = false, bool code = true, bool deleteOriginalOnReturn = true]) async {
  final result = await confirmation("test", context, inDms: dms, useCode: code, deleteOriginalOnReturn: deleteOriginalOnReturn);
  await context.respond(MessageBuilder(embeds: [result.toEmbed()]));
}, permissionsRequired: BotCommandPermissions.owner) : null;
