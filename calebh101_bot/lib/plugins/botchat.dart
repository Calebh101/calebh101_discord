import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';

class BotChatPlugin extends BotPlugin {
  BotChatPlugin() : super(id: "botchat", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("chat", "Chat", "Chat with the bot!", (ChatContext context, [GreedyString? input]) async {
        final chain = BotChatServerSettings(store, context.guild!.id).chain.get();
        final results = await Future(() => chain.generate(input?.data)).timeout(Duration(seconds: 10));

        await context.respond(MessageBuilder(
          content: results.join(" ").nullIfEmpty ?? "No message returned.",
          allowedMentions: AllowedMentions(),
        ));
      }, aliases: ["c"], needsGuild: true),
      BotCommand("train", "Chat", "Train on messages in a channel.", (ChatContext context, int limit, GreedyGuildTextChannelList channels) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get();
        final messages = (await Future.wait<List<Message>>(channels.input.map((x) async => await getAllMessages(x, limit: limit)))).flattened;
        chain.train(messages.map((x) => x.content.split(" ")).flatten().toList());
        settings.chain.set(chain);
        await context.respond(MessageBuilder(content: "Trained on **${messages.length}** messages (**${channels.input.length}** channels). There are now **${chain.chain.length}** total entries."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("trained", "Chat", "Train on messages in a channel.", (ChatContext context) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get();
        final total = chain.chain.entries.map((x) => x.key.length + x.value.map((x) => x.length).sum).sum;
        await context.respond(MessageBuilder(content: "There are **${chain.chain.length}** total entries (**$total** total characters)."));
      }, needsGuild: true),
      BotCommand("prunetrained", "Chat", "Train on messages in a channel.", (ChatContext context, int entries) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        final chain = settings.chain.get();
        if (entries > chain.chain.entries.length || entries <= 0) return context.respondWithError("Too many or too little entries specified.");

        chain.chain = Map.fromEntries(chain.chain.entries.toList().sublist(0, chain.chain.entries.length - entries));
        settings.chain.set(chain);
        await context.respond(MessageBuilder(content: "There are now **${chain.chain.length}** total entries."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setbotchatchannel", "Chat", "Set the bot chatting channel.", (ChatContext context, GuildTextChannel channel) async {
        final settings = BotChatServerSettings(store, context.guild!.id);
        settings.botchatChannel.set(channel.id);
        await context.respond(MessageBuilder(content: "Bot chat channel set to ${channel.toMention()}."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
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
        final chain = BotChatServerSettings(store, event.guildId!).chain.get();

        try {
          final results = await Future(() => chain.generate(event.message.content)).timeout(Duration(seconds: 10));

          await event.message.channel.sendMessage(MessageBuilder(
            content: results.isNotEmpty ? results.join(" ") : "No message sent.",
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
  SettingsObjectNotNull<MarkovChain> get chain => SettingsObjectNotNull(this, "markovChain", encodeFunction: (input) => jsonEncode(input.chain), decodeFunction: (input) => input != null ? MarkovChain.fromChain(RecursiveCaster.cast<Map<String, List<String>>>(jsonDecode(input))) : null, defaultFunction: () => MarkovChain());
}

class MarkovChain {
  final int order;
  Map<String, List<String>> chain = {};
  final Random random = Random();

  MarkovChain({this.order = 1});
  MarkovChain.fromChain(this.chain, {this.order = 1});

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