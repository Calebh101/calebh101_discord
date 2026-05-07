import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class QuotePlugin extends BotPlugin {
  QuotePlugin() : super(id: "quote", version: Version.parse("1.0.0A"));

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onMessageReactionAdd.listen((event) async {
        if (event.guildId == null || event.member == null) return;
        final settings = QuoteSettings(context.store, event.guildId!);

        final guild = await event.guild!.get();
        final emoji = await settings.getQuoteEmoji(client: client, guild: guild);
        if (emoji == null) return;

        final channelId = settings.quoteChannel.get();
        if (channelId == null) return;
        late GuildTextChannel channel;

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Quote", "Unable to get channel $channelId: $e");
          return;
        }

        final count = settings.quoteCount.get();
        final message = await event.message.get();

        final reactions = Map.fromEntries(await Future.wait(message.reactions.map((x) async {
          final emoji = await x.emoji.get();
          return MapEntry(emoji, await message.fetchReactions(ReactionBuilder.fromEmoji(emoji)));
        })));

        final reaction = reactions.entries.firstWhereOrNull((x) => x.key.id == emoji.id && x.key.name == emoji.name);

        if (reaction?.value.any((x) => x.id == client.user.id) ?? false) {} else {
          final users = reaction?.value.where((x) => !x.isBot && !x.isSystem && x.id != event.userId) ?? [];
          if (isAdmin(settings: settings, member: event.member!) && settings.quoteAdminImmediate.get()) {} else if (users.length < count) return;
        }

        await channel.sendMessage(MessageBuilder(embeds: [EmbedBuilder(
          description: "Quote by ${message.author.id.value.toMention()}\n\n${message.content}",
          timestamp: DateTime.now().toUtc(),
          color: await getColor(await tryCatchA<Member?>(() async => await userToMember(message.author as User, guild: guild))),
        )]));
      });
    });
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