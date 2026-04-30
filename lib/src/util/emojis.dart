import 'dart:async';

import 'package:async/async.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class EmojiListDetails {
  final List<Emoji> emojis;
  const EmojiListDetails(this.emojis);
}

Future<EmojiListDetails?> askForEmojis(ChatContext context, [int? required]) async {
  Future<void> Function() onTimeUp = () async {
    Logger.warn("Emojis", "askForEmojis session with user ${context.user.id} has not set onTimeUp at this point. The message will appear broken.");
  };

  int secondsRemaining = 300;
  List<Emoji> emojis = [];

  final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
    secondsRemaining--;

    if (secondsRemaining <= 0) {
      Logger.print("Confirmation", "Confirmation session with user ${context.user.id} hit time limit.");
      onTimeUp.call();
      timer.cancel();
    }
  });

  try {
    final message = await context.channel.sendMessage(MessageBuilder(content: "To select emojis, react to this message with ${required != null ? "**$required**" : "any"} emojis.\nReact with :stop_button: to ${required != null ? "cancel" : "stop"}."));
    final controller = StreamController<GatewayEvent>();

    StreamGroup.merge([
      context.client.onMessageReactionAdd,
      context.client.onMessageReactionRemove,
    ]).listen(
      (event) => controller.isClosed ? null : controller.add(event),
      onDone: () => controller.close(),
    );

    onTimeUp = () async {
      controller.close();
    };

    await for (final event in controller.stream) {
      if (event is MessageReactionAddEvent) {
        if (event.userId != context.user.id || event.messageId != message.id) continue;

        if (event.emoji.name == "⏹️") {
          controller.close();
          break;
        } else {
          secondsRemaining = 300;
          emojis.add(event.emoji);
          await event.message.react(ReactionBuilder.fromEmoji(event.emoji));
        }
      } else if (event is MessageReactionRemoveEvent) {
        if (event.userId != context.user.id || event.messageId != message.id) continue;
        secondsRemaining = 300;
        await event.message.deleteOwnReaction(ReactionBuilder.fromEmoji(event.emoji));
        emojis.remove(event.emoji);
      }
    }

    if (emojis.length == required || (required == null && emojis.isNotEmpty)) {
      return EmojiListDetails(emojis);
    } else {
      return null;
    }
  } catch (e) {
    Logger.warn("Emojis", "Error: $e");
    return null;
  }
}