import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';

class GuildCarrier {
  final Guild guild;
  const GuildCarrier(this.guild);
}

class BotChatPlugin extends BotPluginLegacy {
  BotChatPlugin() : super(id: "botchat", version: Version.parse("1.0.0A"));

  MarkovChain newChain(dynamic context) {
    final Guild guild = context.guild!;
    return MarkovChain(order: BotChatServerSettings(store, guild.id).botchatOrder.get() ?? 1);
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("chat", "Chat", "Chat with the bot!", (ChatContext context, [GreedyString? input]) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get() ?? newChain(context);
        final messages = await getAllMessages(context.channel, limit: settings.botChatContextTraining.get());
        chain.train(messages.map((x) => x.content.split(" ")).flatten().toList());
        final results = await Future(() => chain.generate(input?.data)).timeout(Duration(seconds: 10));

        await context.respond(MessageBuilder(
          content: results.join(" ").toLowerCase().nullIfEmptyTrimmed ?? "No message returned.",
          allowedMentions: AllowedMentions(),
        ));
      }, needsGuild: true),
      BotCommand("train", "Chat", "Train on messages in a channel.", (ChatContext context, int limit, GreedyGuildTextChannelList channels) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get() ?? newChain(context);
        final messages = (await Future.wait<List<Message>>(channels.input.map((x) async => await getAllMessages(x, limit: limit)))).flattened;
        chain.train(messages.where((x) => x.author is User && !(x.author as User).isBot).map((x) => x.content.split(" ")).flatten().toList());
        settings.chain.set(chain);
        await context.respond(MessageBuilder(content: "Trained on **${messages.length}** messages (**${channels.input.length}** channels). There are now **${chain.chain.length}** total entries."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("trained", "Chat", "See the bot's training data.", (ChatContext context) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get() ?? newChain(context);
        final total = chain.chain.entries.map((x) => x.key.length + x.value.map((x) => x.length).sum).sum;
        await context.respond(MessageBuilder(content: "There are **${chain.chain.length}** total entries (**$total** total characters).\n\nOrder: **${chain.order}**\nContext window: **${settings.botChatContextTraining.get()}**"));
      }, needsGuild: true),
      BotCommand("prunetrained", "Chat", "Remove random entries that the bot has trained on.", (ChatContext context, int entries) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get() ?? newChain(context);
        if (entries > chain.chain.entries.length || entries <= 0) return context.respondWithError("Too many or too little entries specified.");

        chain.chain = Map.fromEntries(chain.chain.entries.toList().sublist(0, chain.chain.entries.length - entries));
        settings.chain.set(chain);
        await context.respond(MessageBuilder(content: "There are now **${chain.chain.length}** total entries."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("cleartrained", "Chat", "Remove all entries that the bot has trained on, and optionally set the order.", (ChatContext context, [int? order]) async {
        if ((order ?? 0) < 1) return context.respondWithError("Invalid order: `$order`");
        final settings = BotChatServerSettings(store, context.guild!.id);
        settings.botchatOrder.set(order);
        settings.chain.set(newChain(context));
        await context.respond(MessageBuilder(content: "Chain cleared. New order: ${order != null ? "**$order**" : "Not specified"}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setbotchatchannel", "Chat", "Set the bot chatting channel.", (ChatContext context, GuildTextChannel channel) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        settings.botchatChannel.set(channel.id);
        await context.respond(MessageBuilder(content: "Bot chat channel set to ${channel.toMention()}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setbotchatcontext", "Chat", "Bot chat context window.", (T context, int? value) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        settings.botChatContextTraining.set(value);
        final result = settings.botChatContextTraining.get();

        await context.respond(MessageBuilder(content: "Botchat context set to **$result**!"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true, extendedDescription: "Each time someone chats with the bot, the Markov chain will be temporarily trained with the last X messages in the current channel. This training data will not be saved after the response."),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onMessageCreate.listen((event) async {
        if (isIgnored(store, event.message.author.id)) return;
        if (event.message.author is! User) return;
        if (event.guild == null) return;

        final user = event.message.author as User;
        if (user.isBot || user.isSystem) return;

        final settings = BotChatServerSettings(store, event.guildId!);
        if (event.message.content.startsWith(settings.prefix.get())) return;
        if (!settings.botchatChannel.exists() || event.message.channelId != settings.botchatChannel.get()) return;
        await event.message.channel.triggerTyping();
        final chain = BotChatServerSettings(store, event.guildId!).chain.get() ?? newChain(GuildCarrier(await event.guild!.get()));

        try {
          final channel = await event.message.channel.get() as TextChannel;
          final messages = await getAllMessages(channel, limit: settings.botChatContextTraining.get());
          chain.train(messages.map((x) => x.content.split(" ")).flatten().toList());
          final results = await Future(() => chain.generate(event.message.content)).timeout(Duration(seconds: 10));

          await event.message.channel.sendMessage(MessageBuilder(
            content: results.isNotEmpty ? results.join(" ").toLowerCase() : "No message sent.",
            allowedMentions: AllowedMentions(),
            referencedMessage: MessageReferenceBuilder.reply(messageId: event.message.id),
          ));
        } catch (e) {
          Logger.warn("Botchat", "Unable to send message in channel ${event.message.channelId}: $e");
        }
      });
    });
  }
}

class BotChatServerSettings extends Calebh101BotServerSettings {
  BotChatServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get botchatChannel => SettingsObject.snowflake(this, "botchatChannel");
  SettingsObject<int> get botchatOrder => SettingsObject(this, "botchatOrder");
  SettingsObjectNotNull<int> get botChatContextTraining => SettingsObjectNotNull(this, "context", defaultFunction: () => 10);
  SettingsObject<MarkovChain> get chain => SettingsObject(this, "markovChain", encodeFunction: (input) => jsonEncode(input.toJson()), decodeFunction: (input) => input != null ? MarkovChain.fromJson(jsonDecode(input)) : null);
}

class MarkovChain {
  final int order;
  Map<String, List<String>> chain = {};
  final Random random = Random();

  MarkovChain({this.order = 1});
  MarkovChain.fromChain(this.chain, {this.order = 1});

  Map toJson() {
    return {
      "order": order,
      "chain": chain,
    };
  }

  static MarkovChain fromJson(Map data) {
    return MarkovChain.fromChain(RecursiveCaster.cast<Map<String, List<String>>>(data["chain"]), order: data["order"] is int ? data["order"] : 1);
  }

  void train(List<String> tokens) {
    for (int i = 0; i < tokens.length - order; i++) {
      final key = tokens.sublist(i, i + order).join(' ');
      final next = tokens[i + order];
      chain.putIfAbsent(key, () => []).add(next);
    }
  }

  List<String> generate([String? input]) {
    final length = random.nextInt(20) + 5;
    if (chain.isEmpty) return [];

    final keys = chain.keys.toList();
    late String currentKey;

    if (input != null) {
      final inputWords = input.toLowerCase().trim().split(RegExp(r'\s+'));

      final matchingKeys = keys.where((key) {
        final keyWords = key.toLowerCase().split(' ');
        return inputWords.any((word) => keyWords.contains(word));
      }).toList();

      if (matchingKeys.isNotEmpty) {
        currentKey = matchingKeys[random.nextInt(matchingKeys.length)];
      } else {
        currentKey = keys[random.nextInt(keys.length)];
      }
    } else {
      currentKey = keys[random.nextInt(keys.length)];
    }

    final result = currentKey.split(' ');

    for (int i = 0; i < length; i++) {
      final nextOptions = chain[currentKey];
      if (nextOptions == null || nextOptions.isEmpty) break;

      final next = nextOptions[random.nextInt(nextOptions.length)];
      result.add(next);

      final keyParts = currentKey.split(' ')..removeAt(0);
      keyParts.add(next);
      currentKey = keyParts.join(' ');
    }

    return result;
  }
}