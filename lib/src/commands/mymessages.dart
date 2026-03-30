import 'package:calebh101_discord/calebh101_discord.dart';

BotCommand sendMessageAs() => BotCommand.command("sendmessage", "Send a message on my behalf.", (ChatContext context, String content, [GuildTextChannel? channel, Snowflake? reply]) async {
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

BotCommand deleteMyMessageCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command(
  "deletemessage", "Delete my message.",
  (ChatContext context, Snowflake id, [GuildTextChannel? targetChannel]) async {
    final owner = isOwner(id: context.user.id);

    if (context.guild != null && !owner) {
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("No settings found.");
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

BotCommand editMyMessageCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command(
  "editmessage", "Edit a message of mine.",
  (ChatContext context, Snowflake id, String content, [GuildTextChannel? targetChannel]) async {
    final owner = isOwner(id: context.user.id);

    if (context.guild != null && !owner) {
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("No settings found.");
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