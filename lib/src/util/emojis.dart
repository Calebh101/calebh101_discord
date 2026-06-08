import 'dart:async';

import 'package:async/async.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:unicode/blocks.dart';

class EmojiListDetails {
  final List<Emoji> emojis;
  final Message sentMessage;

  const EmojiListDetails(this.emojis, {required this.sentMessage});
}

Future<EmojiListDetails?> askForEmojis(ChatContext context, {int? required, String? prompt, bool allowCustom = true}) async {
  Future<void> Function() onTimeUp = () async {
    Logger.warn("Emojis", "askForEmojis session with user ${context.user.id} has not set onTimeUp at this point. The message will appear broken.");
  };

  int secondsRemaining = 300;
  List<Emoji> emojis = [];
  Message? message;

  final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
    secondsRemaining--;

    if (secondsRemaining <= 0) {
      Logger.print("Confirmation", "Confirmation session with user ${context.user.id} hit time limit.");
      onTimeUp.call();
      timer.cancel();
    }
  });

  try {
    message = await context.channel.sendMessage(MessageBuilder(content: prompt ?? "To select emojis, react to this message with ${required != null ? "**$required**" : "any"} emojis.\n${allowCustom ? "Custom emojis are allowed." : "Custom emojis are **not** allowed."}\nReact with :stop_button: to ${required != null ? "cancel" : "stop"}."));
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
        } else if (allowCustom || event.emoji.name != null) {
          secondsRemaining = 300;
          emojis.add(event.emoji);

          await event.message.react(ReactionBuilder.fromEmoji(event.emoji));
          if (required != null && emojis.length >= required) break;
        }
      } else if (event is MessageReactionRemoveEvent) {
        if (event.userId != context.user.id || event.messageId != message.id) continue;
        secondsRemaining = 300;
        await event.message.deleteOwnReaction(ReactionBuilder.fromEmoji(event.emoji));
        emojis.remove(event.emoji);
      }
    }

    if (emojis.length == required || (required == null && emojis.isNotEmpty)) {
      return EmojiListDetails(emojis, sentMessage: message);
    } else {
      return null;
    }
  } catch (e) {
    Logger.warn("Emojis", "Error: $e");
    return null;
  }
}

final emojiBlocks = [UnicodeBlock.miscellaneousSymbols, UnicodeBlock.dingbats, UnicodeBlock.miscellaneousSymbolsandArrows, UnicodeBlock.enclosedAlphanumerics, UnicodeBlock.miscellaneousSymbolsandPictographs, UnicodeBlock.emoticons, UnicodeBlock.ornamentalDingbats, UnicodeBlock.transportandMapSymbols, UnicodeBlock.alchemicalSymbols, UnicodeBlock.geometricShapesExtended, UnicodeBlock.supplementalArrowsC, UnicodeBlock.supplementalSymbolsandPictographs, UnicodeBlock.chessSymbols, UnicodeBlock.symbolsandPictographsExtendedA, UnicodeBlock.symbolsforLegacyComputing, UnicodeBlock.enclosedAlphanumericSupplement, UnicodeBlock.enclosedIdeographicSupplement, UnicodeBlock.mahjongTiles, UnicodeBlock.dominoTiles, UnicodeBlock.playingCards];

Future<Emoji?> parseEmoji(String input, {required NyxxGateway client, required Guild? guild}) async {
  input = input.trim();

  if (input.runes.length == 1) {
    if (emojiBlocks.contains(getUnicodeBlock(input.runes.first))) {
      return client.getTextEmoji(input);
    }
  } else if (input.isNotEmpty) {
    final regex = RegExp(r'<:([^<>:]+):(\d+)>');
    final match = regex.firstMatch(input);

    if (match != null) {
      final name = match.group(1)!;
      final id = Snowflake(int.parse(match.group(2)!));

      return await guild?.emojis.fetch(id);
    }
  }

  return null;
}

Map emojiToJson(Emoji emoji) {
  return {
    "type": emoji is TextEmoji ? 0 : emoji is GuildEmoji ? 1 : null,
    "id": emoji.id.value,
    "name": emoji.name,
  };
}

Future<Emoji?> emojiFromJson(Map input, {required NyxxGateway client, required Guild? guild}) async {
  switch (input["type"]) {
    case 0:
      return client.getTextEmoji(input["name"]);
    case 1:
      return await guild?.emojis.get(Snowflake(input["id"]));
  }

  return null;
}

String? emojiToString(Emoji emoji) {
  if (emoji.id.value > 0) {
    return "<:${emoji.name}:${emoji.id}>";
  } else {
    return emoji.name;
  }
}

extension EmojiToString on Emoji {
  String? toDiscordString() {
    return emojiToString(this);
  }
}