import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

Future<Map<int, String>> parseRules(String text, KVStore store) async {
  final settings = RulesBotSettings(store);
  final regex = settings.rulesRegex.get() ?? RegExp(r'(?=^(?:Rule\s+)?\d+\.]s+)', multiLine: true);
  Logger.print("Rules", "Using pattern: $regex");

  return Map.fromEntries((await Future.wait(
    text.split(regex).map((s) => s.trim()).where((s) => s.isNotEmpty)
      .map((s) async {
        final match = await safematch(RegExp(r'^\d+'), (p) => p.firstMatch(s));
        if (match == null) return null;
        final num = int.parse(match.group(0)!);
        final content = s.replaceFirst(RegExp(r'^\d+\. '), '').trim();
        return MapEntry(num, content);
      }))).whereType<MapEntry<int, String>>(),
  );
}

class RulesPlugin extends BotPlugin {
  RulesPlugin() : super(id: "rules", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyStringList.converter(),
      dateTimeConverter(),
    ];
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("rules", "Rules", "Get all the rules.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = settings.rules.get() ?? {};

        if (rules.isEmpty) return context.respondWithError("No rules set. Add some with either `setrules` or `parserules`!");
        await context.respond(MessageBuilder(content: rules.entries.map((x) => "${x.key}. ${x.value}").join("\n")));
      }),
      BotCommand("rule", "Rules", "Get a specific rule.", (T context, int index) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = settings.rules.get() ?? {};

        if (rules.isEmpty) return context.respondWithError("No rules set. Add some with either `setrules` or `parserules`!");
        if (!rules.containsKey(index)) return context.respondWithError("Rule $index not found.");
        await context.respond(MessageBuilder(content: "## Rule #$index\n${rules[index]}"));
      }),
      BotCommand("setrules", "Rules", "Set the rules.", (T context, GreedyString input) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        final rules = await parseRules(input.data, store);
        if (rules.isEmpty) return context.respondWithError("No rules were able to be parsed.");
        settings.rules.set(rules);
        await context.respond(MessageBuilder(content: "Rules set. Run `rules` to view."));
      }),
      BotCommand("setrulesfrom", "Rules", "Set a rule from a message ID.", (T context, Snowflake messageId, [Snowflake? channelId]) async {
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
        final rules = await parseRules(message.content, store);
        if (rules.isEmpty) return context.respondWithError("No rules were able to be parsed.");
        settings.rules.set(rules);
        await context.respond(MessageBuilder(content: "Rules set. Run `rules` to view."));
      }),
      BotCommand("setrulesfromall", "Rules", "Set a rule from messages in a range..", (T context, GuildTextChannel? channel, [Snowflake? after, Snowflake? before]) async {
        if (await context.assureGuild() == false) return;
        final settings = Calebh101BotServerSettings(store, context.guild!.id);

        final message = await tryCatchA<List<Message>?>(() async {
          final c = await tryCatchA(() => context.client.channels.get(channel?.id ?? context.guild?.rulesChannelId ?? (throw Exception())), onCatch: (_) => context.channel) as GuildTextChannel;
          final messages = await tryCatchA(() => c.messages.fetchMany(after: after, before: before));

          if (messages == null) {
            context.respondWithError("Unable to fetch messages from channel ${c.toMention()}.");
            return null;
          }

          return messages;
        });

        if (message == null) return;
        final content = message.sorted((a, b) => a.timestamp.compareTo(b.timestamp)).map((x) => x.content).join("\n");
        if (dev) Logger.print("Rules", "Content ($before-$after):\n$content");

        final rules = await parseRules(content, store);
        if (rules.isEmpty) return context.respondWithError("No rules were able to be parsed.");
        settings.rules.set(rules);
        await context.respond(MessageBuilder(content: "Rules set. Run `rules` to view."));
      }),
      BotCommand("rulesregex", "Rules", "Get the current rules regex.", (T context) async {
        final settings = RulesBotSettings(store);
        final pattern = settings.rulesRegex.get();

        await context.respond(MessageBuilder(
          content: pattern != null ? "Rules pattern:\n${pattern.pattern.toDiscordCodeBlock()}" : "No rules regex set.",
        ));
      }),
      BotCommand("setrulesregex", "Rules", "Set the current rules regex.", (T context, GreedyString pattern) async {
        final settings = RulesBotSettings(store);
        settings.rulesRegex.set(RegExp(pattern.data));

        await context.respond(MessageBuilder(
          content: "Rules pattern set:\n${pattern.toDiscordCodeBlock()}",
        ));
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("resetrulesregex", "Rules", "Set the current rules regex.", (T context) async {
        final settings = RulesBotSettings(store);
        settings.rulesRegex.delete();

        await context.respond(MessageBuilder(
          content: "Rules regex set.",
        ));
      }, permissionsRequired: BotCommandPermissions.owner),
    ];
  }
}

class RulesBotSettings extends BotSettings {
  RulesBotSettings(super.store);

  SettingsObject<RegExp> get rulesRegex => SettingsObject(this, "rulesRegex", encodeFunction: (input) => input.pattern.replaceAll("\\\\", "\\"), decodeFunction: (input) => input != null ? RegExp(input, multiLine: true) : null);
}