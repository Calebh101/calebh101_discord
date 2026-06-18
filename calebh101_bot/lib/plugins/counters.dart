import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class CountersPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "counters", version: Version.parse("1.0.0A"), description: "Simple counters.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("count", "Counters", "Increase a counter.", (T context, String name) async {
        final settings = CountersSettings(store, context.userId);
        final counter = settings.counters.get()[name];

        if (counter == null) return context.respondWithError("Couldn't find counter: $name");
        await context.respond(MessageBuilder(content: "`$name` = **$counter**"));
      }, aliases: ["c", "#"]),

      BotCommand("increase", "Counters", "Increase a counter.", (T context, String name, [int amount = 1]) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters[name] = counters[name]! + amount;
        settings.counters.set(counters);

        if (context is MessageChatContext) await context.message.react(checkmark);
        else await context.respond(MessageBuilder(content: "`$name` = **${counters[name]}**"), level: .hint);
      }, triggerTyping: false, aliases: ["+"]),

      BotCommand("decrease", "Counters", "Decrease a counter.", (T context, String name, [int amount = -1]) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters[name] = counters[name]! - amount;
        settings.counters.set(counters);

        if (context is MessageChatContext) await context.message.react(checkmark);
        else await context.respond(MessageBuilder(content: "`$name` = **${counters[name]}**"), level: .hint);
      }, triggerTyping: false, aliases: ["-"]),

      BotCommand("setcount", "Counters", "Decrease a counter.", (T context, String name, int amount) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters[name] = amount;
        settings.counters.set(counters);

        if (context is MessageChatContext) await context.message.react(checkmark);
        else await context.respond(MessageBuilder(content: "`$name` = **${counters[name]}**"), level: .hint);
      }, triggerTyping: false, aliases: ["set"]),

      BotCommand("resetcount", "Counters", "Decrease a counter.", (T context, String name) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters[name] = 0;
        settings.counters.set(counters);

        if (context is MessageChatContext) await context.message.react(checkmark);
        else await context.respond(MessageBuilder(content: "`$name` = **${counters[name]}**"), level: .hint);
      }, triggerTyping: false, aliases: ["reset"]),

      BotCommand("newcounter", "Counters", "Make a new counter.", (T context, String name) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (counters.containsKey(name)) return context.respondWithError("Counter already exists.");
        counters[name] = 0;
        settings.counters.set(counters);

        await context.respond(MessageBuilder(content: "Counter created: `$name`"));
      }),

      BotCommand("counters", "Counters", "Find all your counters.", (T context) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        await context.respond(MessageBuilder(content: counters.isEmpty ? "You have no counters!" : "You have **${counters.length}** counters:\n\n${counters.mapTo((k, v) {
          return "- `$k`: **$v**";
        }).join("\n")}"));
      }, aliases: ["listcounters"]),

      BotCommand("remcounter", "Counters", "Delete a counter.", (T context, String name) async {
        final settings = CountersSettings(store, context.userId);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters.remove(name);
        settings.counters.set(counters);

        await context.respond(MessageBuilder(content: "Counter deleted: `$name`"));
      }, aliases: ["delcounter"]),

      BotCommand("remcounterof", "Counters", "Delete a counter of someone.", (T context, User user, String name) async {
        final settings = CountersSettings(store, user.id);
        final counters = settings.counters.get();

        if (!counters.containsKey(name)) return context.respondWithError("Couldn't find counter: $name");
        counters.remove(name);
        settings.counters.set(counters);

        await context.respond(MessageBuilder(content: "Counter deleted: `$name`"));
      }, aliases: ["delcounterof"], permissionsRequired: .owner),
    ];
  }
}

class CountersSettings extends UserSettings {
  CountersSettings(super.store, super.id);

  SettingsObjectNotNull<Map<String, int>> get counters => SettingsObject.map(this, "counters");
}