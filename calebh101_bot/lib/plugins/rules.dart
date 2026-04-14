import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

Map<int, String> parseRules(String text) {
  final regex = RegExp(r'(?=^\d+\. )', multiLine: true);

  return Map.fromEntries(
    text
      .split(regex)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) {
        final match = RegExp(r'^\d+').firstMatch(s);
        if (match == null) return null;
        final num = int.parse(match.group(0)!);
        final content = s.replaceFirst(RegExp(r'^\d+\. '), '').trim();
        return MapEntry(num, content);
      })
      .whereType<MapEntry<int, String>>(),
  );
}

class RulesPlugin extends BotPlugin {
  RulesPlugin() : super(id: "rules", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyStringList.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("rules", "Rules", "Get all the rules.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = settings.rules.get() ?? {};

        if (rules.isEmpty) return context.respondWithError("No rules set. Add some with either `setrules` or `parserules`!");
        await context.respond(MessageBuilder(content: rules.entries.map((x) => "${x.key}. ${x.value}").join("\n")));
      }),
      BotCommand("rule", "Rules", "Get a specific rule.", (ChatContext context, int index) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = settings.rules.get() ?? {};

        if (rules.isEmpty) return context.respondWithError("No rules set. Add some with either `setrules` or `parserules`!");
        if (!rules.containsKey(index)) return context.respondWithError("Rule $index not found.");
        await context.respond(MessageBuilder(content: "## Rule #$index\n${rules[index]}"));
      }),
      BotCommand("setrules", "Rules", "Set the rules.", (ChatContext context, GreedyString input) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = parseRules(input.data);
        if (rules.isEmpty) return context.respondWithError("No rules were able to be parsed.");
        settings.rules.set(rules);
        await context.respond(MessageBuilder(content: "Rules set. Run `rules` to view."));
      }),
      BotCommand("setrulesfrommessage", "Rules", "Set a rule from a message ID.", (ChatContext context, Snowflake messageId, [Snowflake? channelId]) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);

        final message = await tryCatchA<Message?>(() async {
          final channel = await tryCatchA(() => context.client.channels.get(channelId ?? context.guild?.rulesChannelId ?? (throw Exception())), onCatch: (_) => context.channel) as GuildTextChannel;
          final message = await tryCatchA(() => channel.messages.get(messageId));

          if (message == null) {
            context.respondWithError("Unable to fetch message ID from channel ${channel.toMention()}.");
            return null;
          }

          return message;
        });

        if (message == null) return;
        final rules = parseRules(message.content);
        if (rules.isEmpty) return context.respondWithError("No rules were able to be parsed.");
        settings.rules.set(rules);
        await context.respond(MessageBuilder(content: "Rules set. Run `rules` to view."));
      }),
    ];
  }
}