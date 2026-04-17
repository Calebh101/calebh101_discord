import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';

class MessagesPlugin extends BotPlugin {
  MessagesPlugin() : super(id: "messages", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      sendMessageAs<T>(),
      deleteMyMessageCommand<T>(store),
      editMyMessageCommand<T>(store),
      messageMe<T>(),

      BotCommand("collapse", "Bot", "Collapse a message of mine, by removing embeds, attachments, and extra text.", (ChatContext context, Snowflake id, [GuildTextChannel? targetChannel]) async {
        String getNew(String current) {
          final lines = current.split("\n");
          final target = lines.sublist(0, min(3, lines.length));
          final text = target.join("\n");
          final data = text.substring(0, min(50, text.length));
          final changed = lines.length != target.length || current != data;
          final result = "$data${changed ? "..." : ""}";
          return result.isEmpty ? "||Collapsed||" : result;
        }

        final channel = targetChannel ?? context.channel;

        try {
          final message = await channel.messages.get(id);
          if (message.author.id != context.client.user.id) return context.respondWithError("This message is not mine.", level: ResponseLevel.hint);
          await message.edit(MessageUpdateBuilder(content: getNew(message.content), attachments: [], embeds: []));
          await context.respond(MessageBuilder(content: "Message `${message.id}` edited."), level: ResponseLevel.hint);
        } catch (e) {
          Logger.warn("CollapseMyMessage", "Unable to edit message $id in channel ${channel.id}: $e");
          context.respondWithError("Unable to edit message.", level: ResponseLevel.private);
        }
      }, permissionsRequired: BotCommandPermissions.owner),
    ];
  }

  BotCommand sendMessageAs<T extends ChatContext>() => BotCommand.command("sendmessage", "Send a message on my behalf.", (T context, String content, [GuildTextChannel? channel, Snowflake? reply]) async {
    if (await context.assureOwner() == false) return;
    final c = channel ?? context.channel;
    if (c is! GuildTextChannel) return context.respondWithError("The selected channel is not a valid channel.\nExpected: `GuildTextChannel`, got: `${c.runtimeType}`");
    if (context.guild == null) return context.respondWithError("No guild found.");

    try {
      await c.sendMessage(MessageBuilder(content: content, referencedMessage: reply != null ? MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: reply, failIfInexistent: false) : null));
      await context.respond(MessageBuilder(content: "Message sent to ${c.toMention()}.\n-# Reply ID: ${reply.toDiscordCodeString()}"), level: ResponseLevel.hint);
    } catch (e) {
      Logger.warn("SendMessageAs", "Unable to send message from ${channel?.id}: $e");
      context.respondWithError("Unable to send message.", level: ResponseLevel.private);
    }
  }, CommandAttributes(category: "Bot"));

  BotCommand deleteMyMessageCommand<T extends ChatContext>(KVStore store) => BotCommand.command(
    "deletemessage", "Delete my message.",
    (T context, Snowflake id, [GuildTextChannel? targetChannel]) async {
      final owner = isOwner(id: context.user.id);

      if (context.guild != null && !owner) {
        final settings = ServerSettings(store, context.guild!.id);
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      } else {
        if (!owner) return context.respondWithError("You are not the owner of me.");
      }

      final channel = targetChannel ?? context.channel;

      try {
        final message = await channel.messages.get(id);
        if (message.author.id != context.client.user.id) return context.respondWithError("This message is not mine.", level: ResponseLevel.hint);
        await message.delete();
        await context.respond(MessageBuilder(content: "Message `${message.id}` deleted."), level: ResponseLevel.hint);
      } catch (e) {
        Logger.warn("DeleteMyMessage", "Unable to delete message $id from channel ${channel.id}: $e");
        context.respondWithError("Unable to delete message.", level: ResponseLevel.private);
      }
    },
    CommandAttributes(category: "Bot"),
  );

  BotCommand editMyMessageCommand<T extends ChatContext>(KVStore store) => BotCommand.command(
    "editmessage", "Edit a message of mine.",
    (T context, Snowflake id, String content, [GuildTextChannel? targetChannel]) async {
      final owner = isOwner(id: context.user.id);

      if (context.guild != null && !owner) {
        final settings = ServerSettings(store, context.guild!.id);
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      } else {
        if (!owner) return context.respondWithError("You are not the owner of me.");
      }

      final channel = targetChannel ?? context.channel;

      try {
        final message = await channel.messages.get(id);
        if (message.author.id != context.client.user.id) return context.respondWithError("This message is not mine.", level: ResponseLevel.hint);
        await message.edit(MessageUpdateBuilder(content: content));
        await context.respond(MessageBuilder(content: "Message `${message.id}` edited."), level: ResponseLevel.hint);
      } catch (e) {
        Logger.warn("EditMyMessage", "Unable to edit message $id from channel ${channel.id}: $e");
        context.respondWithError("Unable to edit message.", level: ResponseLevel.private);
      }
    },
    CommandAttributes(category: "Bot"),
  );

  BotCommand messageMe<T extends ChatContext>() => BotCommand.command("messageme", "Make me DM you.", (T context) async {
    bool dmSuccessful = false;

    try {
      (await context.client.users.createDm(context.user.id)).sendMessage(MessageBuilder(
        content: "Hey there, <@${context.user.id}>!",
      ));

      dmSuccessful = true;
    } catch (e) {
      Logger.warn("Commands.Suggestion.Deny", "Unable to open DM: $e");
    }

    await context.respond(MessageBuilder(content: dmSuccessful ? "<@${context.user.id}>, I have DMed you." : "<@${context.user.id}>, I was **not** able to DM you."), level: ResponseLevel.hint);
  }, CommandAttributes(category: "Bot"));
}