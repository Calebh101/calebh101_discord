import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;

class QuotePlugin extends BotPluginLegacy {
  QuotePlugin() : super(id: "quote", version: Version.parse("1.0.0A"));

  Future<String?> quote(NyxxGateway client, KVStore store, MessageReactionAddEvent event) async {
    if (isIgnored(store, event.userId)) return "Ignored";
    if (event.guildId == null || event.member == null) return "No guild/member";

    final settings = QuoteSettings(store, event.guildId!);
    if (settings.quotedMessages.get().contains(event.messageId)) return "Already quoted";

    final guild = await event.guild!.get();
    final data = settings.getForChannel(event.channelId);

    if (data == null) {
      return "No data";
    }

    final emoji = await data.getQuoteEmoji(client: client, guild: guild);
    final channelId = data.channel;

    if (emoji == null) return "No emoji";
    if (channelId == null) return "No channel";
    if (event.message.channelId == channelId && !dev) return "In quote channel";

    Logger.print("Quote", "Attempting to quote message ${event.messageId} with data ${data.name} (${data.runtimeType})");
    late GuildTextChannel channel;

    try {
      channel = await client.channels.get(channelId) as GuildTextChannel;
    } catch (e) {
      Logger.warn("Quote", "Unable to get channel $channelId: $e");
      return "Couldn't get channel";
    }

    final count = data.count;
    if (count < 1) return "Disabled via count";

    final message = await event.message.fetch();
    if (isIgnored(store, message.author.id)) return "Author is ignored";

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
      final users = reaction?.value.where((x) => !x.isBot && !x.isSystem && message.author.id != x.id) ?? [];
      if (settings.quoteAdminImmediate.get() && isMod(settings: settings, member: event.member!)) {} else if (users.length < count) return "Not enough users";
    }

    final messageChannel = await tryCatchA(() async => await message.channel.get() as GuildTextChannel);
    final current = settings.quotedMessages.get();

    current.add(event.messageId);
    settings.quotedMessages.set(current);

    final List<EmbedBuilder> embeds = [];
    final List<Uri> links = [];

    for (final e in message.embeds) {
      switch (e.type) {
        case .article:
        case .link:
        case .rich:
          embeds.add(
            EmbedBuilder(
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
            ),
          );

          break;

        case .gifv:
        case .image:
        case .video:
          final url = e.url ?? e.image?.url ?? e.video?.url;
          Logger.print("Quote", "URL (${e.type.value}): ${e.image?.url}, ${e.video?.url}, ${e.url}");
          if (url != null) links.add(url);
          break;
      }
    }

    await channel.sendMessage(MessageBuilder(content: links.nullIfEmpty?.join(" "), embeds: [
      EmbedBuilder(
        author: EmbedAuthorBuilder(name: author.username, iconUrl: author.avatar?.url),
        thumbnail: author.avatar?.url != null ? EmbedThumbnailBuilder(url: author.avatar!.url) : null,
        description: "## Quote by ${message.author.id.toUserMention()}\n\n${message.content.max(1900)}",
        timestamp: (message.editedTimestamp ?? message.timestamp).toUtc(),
        color: await getColor(await tryCatchA<Member?>(() async => await userToMember(message.author as User, guild: guild))),
        fields: [
          EmbedFieldBuilder(name: "Where", value: [
            if (messageChannel != null) "In: `#${messageChannel.name}`",
            "${discordLink(event.guildId, message.channelId, message.id)}",
          ].join("\n"), isInline: true),
        ],
      ), ...embeds,
    ], attachments: (await Future.wait(message.attachments.map((x) async {
      final data = (await tryCatchA(() => http.get(x.url)))?.bodyBytes;
      Logger.print("Quote", "Attachment ${x.fileName}: ${data?.lengthInBytes}");
      if (data == null) return null;
      return AttachmentBuilder(fileName: x.fileName, data: data);
    }))).whereType<AttachmentBuilder>().toList()));

    return null;
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onMessageReactionAdd.listen((event) async {
        final result = await quote(client, context.store, event);
        Logger.print("Quote", "Quote result: $result (${result.runtimeType})");
      });
    });
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyGuildTextChannelList.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    QuoteData? get(Snowflake guild, String name) {
      return QuoteSettings(store, guild).quoteData.get().firstWhereOrNull((x) => x.name.toLowerCase() == name.trim().toLowerCase());
    }

    return [
      BotCommand("addquotedata", "Quote", "Set quote data for channels. Don't input any channels to wrap all channels.", (T context, String name, [GreedyGuildTextChannelList? data]) async {
        final channels = data?.data.nullIfEmpty;
        final settings = QuoteSettings(store, context.guildIdUnsafe);
        final current = settings.quoteData.get();
        final item = QuoteData(name: name, channelIds: channels?.mapToList((x) => x.id));

        if (current.contains(item)) {
          return context.respondWithError("Quote data already exists with this name!");
        }

        current.add(item);
        settings.quoteData.set(current);

        final prefix = context.getPrintablePrefix(store: store);
        await context.respond(MessageBuilder(content: "Added quote data: `$name`\nUse `${prefix}setquoteemoji`, `${prefix}setquotecount`, `${prefix}setquotechannel` to configure it!"));
      }, permissionsRequired: .admin, needsGuild: true),
      BotCommand("remquotedata", "Quote", "Set quote data for channels. Don't input any channels to wrap all channels.", (T context, String name) async {
        final settings = QuoteSettings(store, context.guildIdUnsafe);
        final current = settings.quoteData.get();
        final target = current.firstWhereOrNull((x) => x.name.trim().toLowerCase() == name.trim().toLowerCase());

        if (target == null) {
          return context.respondWithError("No quote data found with this name.");
        }

        current.removeWhere((x) => x.name.trim().toLowerCase() == name.trim().toLowerCase());
        settings.quoteData.set(current);

        await context.respond(MessageBuilder(content: "Removed quote data: `$name`"));
      }, permissionsRequired: .admin, needsGuild: true),
      BotCommand("listquotedata", "Quote", "Get quote data for channels.", (T context) async {
        final settings = QuoteSettings(store, context.guildIdUnsafe);
        final current = settings.quoteData.get();

        await context.respond(MessageBuilder(content: current.map((data) {
          return "- `${data.name}`: **${data.channelIds?.length ?? "All"}** channels";
        }).join("\n").nullIfEmpty ?? "No quote data!\nUse `${context.getPrintablePrefix(store: store)}addquotedata` to add quote data."));
      }, permissionsRequired: .admin, needsGuild: true),
      BotCommand("quoteinfo", "Quote", "Get info about quoting.", (T context, String name) async {
        final settings = QuoteSettings(store, context.guildIdUnsafe);
        final data = get(context.guildIdUnsafe, name);
        final emoji = await data?.getQuoteEmoji(client: context.client, guild: context.guild);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        await context.respond(MessageBuilder(content: [
          "Emoji to quote: ${emoji?.toDiscordString() ?? "Not set"}",
          ["Reactions to quote: **${data.count}**", if (settings.quoteAdminImmediate.get()) "(mods will immediately)"].join(" "),
          "Quote channel: ${data.channel?.toChannelMention() ?? "Not set"}",
          "Covered channels: **${data.channelIds?.length ?? "All"}**",
        ].join("\n")));
      }, needsGuild: true),
      BotCommand("remquote", "Quote", "Remove a message ID from the quoted list.", (T context, Snowflake id) async {
        final settings = QuoteSettings(store, context.guildId!);
        final current = settings.quotedMessages.get();
        final contains = current.contains(id);

        if (contains) {
          current.remove(id);
          settings.quotedMessages.set(current);
          await context.respond(MessageBuilder(content: "Message `$id` removed from quoted list."));
        } else {
          await context.respond(MessageBuilder(content: "This message was not quoted."));
        }
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("quote", "Quote", "Instantly quote a message.", (T context, [Snowflake? id]) async {
        final settings = QuoteSettings(store, context.guild!.id);
        final data = settings.getForChannel(context.channelId);
        final emoji = await data?.getQuoteEmoji(client: context.client, guild: context.guild);

        if (emoji == null) {
          Logger.print("Quote", "Emoji: ${emoji.runtimeType} (from ${data?.emoji}) (${data.runtimeType}, ${emoji.runtimeType}, ${data?.emoji.runtimeType})");
          return context.respondWithError(data == null ? "No quote data found for this channel." : "No quote emoji set.");
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

        if (context is InteractionChatContext) await context.respond(MessageBuilder(content: "Message `${message.id}` quoted."), level: ResponseLevel.hint);
        else if (context is MessageChatContext) await context.message.react(ReactionBuilder(name: "✅", id: null));
      }, needsGuild: true, triggerTyping: false, permissionsRequired: BotCommandPermissions.admin, aliases: ["q"]),
      BotCommand("setquoteemoji", "Quote", "Set the emoji used to quote.", (T context, String name, [GreedyString? input]) async {
        final emoji = await parseEmoji(input?.data ?? "", client: context.client, guild: context.guild);
        final data = get(context.guildIdUnsafe, name);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        if (emoji == null) {
          data.emoji = null;
          await context.respond(MessageBuilder(content: "Quote emoji removed."));
          return;
        }

        data.emoji = emojiToJson(emoji);
        QuoteSettings(store, context.guildIdUnsafe).saveWith(data);
        await context.respond(MessageBuilder(content: "Quote emoji set to: ${emoji.toDiscordString()}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true, aliases: ["setquotereaction"]),
      BotCommand("setquotecount", "Quote", "Set the reactions required to quote. Set to 0 to disable.", (T context, String name, int input) async {
        final data = get(context.guildIdUnsafe, name);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        data.count = input;
        QuoteSettings(store, context.guildIdUnsafe).saveWith(data);
        await context.respond(MessageBuilder(content: input > 0 ? "**$input** reactions now required to quote." : "Quoting disabled."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setquotechannel", "Quote", "Set the channel quotes will be posted on.", (T context, String name, [GuildTextChannel? channel]) async {
        final data = get(context.guildIdUnsafe, name);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        data.channel = channel?.id;
        QuoteSettings(store, context.guildIdUnsafe).saveWith(data);
        await context.respond(MessageBuilder(content: "Quote channel set to ${channel?.toMention()}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setquotechannels", "Quote", "Set the channels quotes will be received from.", (T context, String name, [GreedyGuildTextChannelList? all]) async {
        final channels = all?.data.nullIfEmpty;
        final data = get(context.guildIdUnsafe, name);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        data.channelIds = channels?.mapToList((x) => x.id);
        QuoteSettings(store, context.guildIdUnsafe).saveWith(data);
        await context.respond(MessageBuilder(content: "Quote channels set to ${channels?.map((x) => x.toMention()).nullIfEmpty?.join(", ") ?? "**all**"}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("getquotechannels", "Quote", "Get the channels quotes will be received from.", (T context, String name) async {
        final data = get(context.guildIdUnsafe, name);

        if (data == null) {
          return context.respondWithError("Quote data not found for `$name`.");
        }

        await context.respond(MessageBuilder(content: "Quote channels currently set to ${data.channelIds?.nullIfEmpty?.map((x) => x.toChannelMention()).join(", ") ?? "**none**"}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("testquote", "Quote", "Test a quote by channel.", (T context, Channel channel) async {
        final data = QuoteSettings(store, context.guildIdUnsafe).getForChannel(channel.id);
        await context.respond(MessageBuilder(content: data != null ? "Found data: `${data.name}`" : "No data found."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
    ];
  }
}

class QuoteData {
  static const defaultCount = 3;

  final String name;
  List<Snowflake>? channelIds;
  Map? emoji;
  int count;
  Snowflake? channel;

  bool get hasChannels => channelIds?.isNotEmpty ?? false;

  QuoteData({required this.name, required this.channelIds, this.emoji, this.count = defaultCount, this.channel});

  Future<Emoji?> getQuoteEmoji({required NyxxGateway client, required Guild? guild}) async {
    return emoji == null ? null : await emojiFromJson(emoji!, client: client, guild: guild);
  }

  factory QuoteData.fromJson(Map data) {
    final channel = data["channel"] as int?;

    return .new(
      name: data["name"],
      channelIds: (data["channels"] as List?)?.mapToList((x) => .new(x)),
      emoji: data["emoji"],
      count: data["count"],
      channel: channel != null ? .new(channel) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "name": name,
      "channels": channelIds?.mapToList((x) => x.value),
      "emoji": emoji,
      "count": count,
      "channel": channel?.value,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) || (other is QuoteData && other.name.trim().toLowerCase() == name.trim().toLowerCase());
  }

  @override
  int get hashCode => name.hashCode;
}

class QuoteSettings extends ServerSettings {
  QuoteSettings(super.store, super.id);

  SettingsObjectNotNull<bool> get quoteAdminImmediate => SettingsObjectNotNull(this, "quoteAdminImmediate", defaultFunction: () => false);
  SettingsObjectNotNull<List<Snowflake>> get quotedMessages => SettingsObject.listSnowflake(this, "quotedMessages");
  SettingsObjectNotNull<List<QuoteData>> get quoteData => SettingsObjectNotNull(this, "quoteData", defaultFunction: () => [], encodeFunction: (input) => input.mapToList((x) => x.toJson()), decodeFunction: (input) => (input as List?)?.mapToList((x) => QuoteData.fromJson(x)).sorted((a, b) => a.hasChannels ? 1 : -1));

  QuoteData? getForChannel(Snowflake channel) {
    final data = quoteData.get();
    final specific = data.firstWhereOrNull((x) => x.channelIds?.contains(channel) ?? false);

    if (specific != null) {
      return specific;
    }

    final all = data.firstWhereOrNull((x) => x.channelIds == null);
    return all;
  }

  void saveWith(QuoteData data) {
    final current = quoteData.get();
    current.remove(data);
    current.add(data);
    quoteData.set(current);
  }
}
