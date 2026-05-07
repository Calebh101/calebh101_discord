import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

class QuotePlugin extends BotPlugin {
  QuotePlugin() : super(id: "quote", version: Version.parse("1.0.0A"));

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onMessageReactionAdd.listen((event) async {
        if (isIgnored(context.store, event.userId)) return;
        if (event.guildId == null || event.member == null) return;
        final settings = QuoteSettings(context.store, event.guildId!);

        final guild = await event.guild!.get();
        final emoji = await settings.getQuoteEmoji(client: client, guild: guild);
        final channelId = settings.quoteChannel.get();

        Logger.print("Quote", "Emoji: ${emoji.runtimeType}, channel: $channelId (${channelId.runtimeType})");
        if (emoji == null) return;
        if (channelId == null) return;
        if (event.message.channelId == channelId) return;
        late GuildTextChannel channel;

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Quote", "Unable to get channel $channelId: $e");
          return;
        }

        final count = settings.quoteCount.get();
        if (count < 1) return;
        final message = await event.message.fetch();
        if (isIgnored(context.store, message.author.id)) return;

        final reactions = Map.fromEntries(await Future.wait(message.reactions.map((x) async {
          final Emoji emoji = (x.emoji is TextEmoji ? x.emoji : (x.emoji is GuildEmoji ? x.emoji : await x.emoji.get())) as Emoji;
          return MapEntry(emoji, await message.fetchReactions(ReactionBuilder.fromEmoji(emoji)));
        })));

        final reaction = reactions.entries.firstWhereOrNull((x) => x.key.id == emoji.id && x.key.name == emoji.name);
        Logger.print("Quote", "Reactions: ${reaction?.value.length} (from ${reactions.length} entries and ${message.reactions.length} reactions): ${reactions.entries.map((x) => "(${x.key.name}, ${x.key.id}, ${x.key.name == emoji.name}, ${x.key.id == emoji.id})")}");
        final author = message.author;

        if (reaction?.value.any((x) => x.id == client.user.id) ?? false) {
          await message.deleteOwnReaction(ReactionBuilder.fromEmoji(emoji));
        } else {
          final users = reaction?.value.where((x) => !x.isBot && !x.isSystem && x.id != event.userId) ?? [];
          if (isMod(settings: settings, member: event.member!) && settings.quoteAdminImmediate.get()) {} else if (users.length < count) return;
        }

        await channel.sendMessage(MessageBuilder(embeds: [EmbedBuilder(
          author: author is User ? EmbedAuthorBuilder(name: author.username, iconUrl: author.avatar.url) : null,
          description: "## Quote by ${message.author.id.value.toMention()}\n\n${message.content}\n\nLink: ${discordLink(event.guildId, message.channelId, message.id)}\n-# This message was sent by a random user, and is not property of this bot.",
          timestamp: DateTime.now().toUtc(),
          color: await getColor(await tryCatchA<Member?>(() async => await userToMember(message.author as User, guild: guild))),
        ), ...message.embeds.map((e) => EmbedBuilder(
          title: e.title,
          description: e.description,
          url: e.url,
          timestamp: e.timestamp,
          color: e.color,
          footer: e.footer != null ? EmbedFooterBuilder(text: e.footer!.text, iconUrl: e.footer!.iconUrl) : null,
          author: e.author != null ? EmbedAuthorBuilder(name: e.author!.name, url: e.author!.url, iconUrl: e.author!.iconUrl) : null,
          image: e.image != null ? EmbedImageBuilder(url: e.image!.url) : null,
          thumbnail: e.thumbnail != null ? EmbedThumbnailBuilder(url: e.thumbnail!.url) : null,
          fields: e.fields?.map((f) => EmbedFieldBuilder(name: f.name, value: f.value, isInline: f.inline)).toList(),
        ))], attachments: (await Future.wait(message.attachments.map((x) async {
          final data = (await tryCatchA(() => http.get(x.url)))?.bodyBytes;
          Logger.print("Quote", "Attachment ${x.fileName}: ${data?.lengthInBytes}");
          if (data == null) return null;
          return AttachmentBuilder(fileName: x.fileName, data: data);
        }))).whereType<AttachmentBuilder>().toList()));
      });
    });
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("quoteinfo", "Quote", "Get info about quoting.", (T context) async {
        final settings = QuoteSettings(store, context.guild!.id);
        final emoji = await settings.getQuoteEmoji(client: context.client, guild: context.guild);

        await context.respond(MessageBuilder(content: [
          "Emoji to quote: ${emoji?.toDiscordString() ?? "Not set"}",
          ["Reactions to quote: **${settings.quoteCount.get()}**", if (settings.quoteAdminImmediate.get()) "(mods will immediately)"].join(" "),
          "Quote channel: ${settings.quoteChannel.get()?.value.toChannel() ?? "Not set"}"
        ].join("\n")));
      }, needsGuild: true),
      BotCommand("quote", "Quote", "Instantly quote a message.", (T context, [Snowflake? id]) async {
        final settings = QuoteSettings(store, context.guild!.id);
        final emoji = await settings.getQuoteEmoji(client: context.client, guild: context.guild);

        if (emoji == null) {
          return context.respondWithError("No quote emoji set.");
        }

        Message? message;

        if (id == null && context is MessageChatContext) {
          final reply = context.message.referencedMessage;
          message = reply;
        }

        if (id != null) {
          try {
            final channel = context.channel;
            message = await channel.messages.get(id);
          } catch (_) {}
        }

        if (message == null) return context.respondWithError("No message found.");
        await message.react(ReactionBuilder.fromEmoji(emoji));
        await context.respond(MessageBuilder(content: "Message `${message.id}` quoted."), level: ResponseLevel.hint);
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.mod, aliases: ["q"]),
      BotCommand("setquoteemoji", "Quote", "Set the emoji used to quote.", (T context, [GreedyString? input]) async {
        final settings = QuoteSettings(store, context.guild!.id);
        final emoji = await parseEmoji(input?.data ?? "", client: context.client, guild: context.guild);

        if (emoji == null) {
          settings.quoteEmoji.delete();
          await context.respond(MessageBuilder(content: "Quote emoji removed."));
          return;
        }

        settings.quoteEmoji.set(emojiToJson(emoji));
        await context.respond(MessageBuilder(content: "Quote emoji set to: ${emoji.toDiscordString()}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true, aliases: ["setquotereaction"]),
      BotCommand("setquotecount", "Quote", "Set the reactions required to quote. Set to 0 to disable.", (T context, int input) async {
        final settings = QuoteSettings(store, context.guild!.id);
        settings.quoteCount.set(input);
        await context.respond(MessageBuilder(content: input > 0 ? "**$input** reactions now required to quote." : "Quoting disabled."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setquotechannel", "Quote", "Set the reactions required to quote. Set to 0 to disable.", (T context, [GuildTextChannel? channel]) async {
        final settings = QuoteSettings(store, context.guild!.id);

        if (channel == null) {
          settings.quoteChannel.delete();
          await context.respond(MessageBuilder(content: "Quote channel reset."));
          return;
        }

        settings.quoteChannel.set(channel.id);
        await context.respond(MessageBuilder(content: "Quote channel set to ${channel.toMention()}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
    ];
  }
}

class QuoteSettings extends ServerSettings {
  QuoteSettings(super.store, super.id);

  SettingsObject<Map> get quoteEmoji => SettingsObject(this, "quoteEmoji");
  SettingsObjectNotNull<int> get quoteCount => SettingsObjectNotNull(this, "quoteCount", defaultFunction: () => 5);
  SettingsObjectNotNull<bool> get quoteAdminImmediate => SettingsObjectNotNull(this, "quoteAdminImmediate", defaultFunction: () => false);
  SettingsObject<Snowflake> get quoteChannel => SettingsObject.snowflake(this, "quoteChannel");

  Future<Emoji?> getQuoteEmoji({required NyxxGateway client, required Guild? guild}) async {
    final e = quoteEmoji.get();
    if (e == null) return null;
    return emojiFromJson(e, client: client, guild: guild);
  }
}