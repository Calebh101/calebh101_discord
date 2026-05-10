import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class PrefixPlugin extends BotPluginLegacy {
  PrefixPlugin() : super(id: "prefix", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return prefixCommands<T>((guild) => ServerSettings(store, guild.id));
  }

  List<BotCommand> prefixCommands<T extends ChatContext>(ServerSettings? Function(Guild guild) getSettings) => [
    BotCommand.command("prefix", "Get the bot's prefix.", (T context) async {
      final prefix = (context.guild != null ? getSettings.call(context.guild!)?.prefix.get() : null) ?? defaultPrefix;

      await context.respond(MessageBuilder(
        content: "Prefix is currently set to `$prefix`.",
      ));
    }, CommandAttributes(category: "Bot")),
    BotCommand.command("setprefix", "Set the bot's prefix.", (T context, String prefix) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("Unable to load settings.");

      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      final old = settings.prefix.get();
      settings.prefix.set(prefix);

      Modlog.add(ModlogEvent(
        "prefix.change",
        guild: context.guild,
        client: context.client,
        title: "Prefix Changed",
        fields: {
          "Was": old.toDiscordCodeBlock(),
          "Now": prefix.toDiscordCodeBlock(),
          "Default": defaultPrefix.toDiscordCodeBlock(),
        },
        settings: settings,
      ));

      await context.respond(MessageBuilder(
        content: "Prefix set to `$prefix`!",
      ));
    }, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.admin)),
    BotCommand.command("resetprefix", "Reset the bot's prefix for this server.", (T context) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("Unable to load settings.");
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final old = settings.prefix.get();
      settings.prefix.delete();

      Modlog.add(ModlogEvent(
        "prefix.change",
        guild: context.guild,
        client: context.client,
        title: "Prefix Reset",
        fields: {
          "Was": old.toDiscordCodeBlock(),
          "Now": null.toDiscordCodeBlock(),
          "Default": defaultPrefix.toDiscordCodeBlock(),
        },
        settings: settings,
      ));

      context.respond(MessageBuilder(
        content: "Prefix set to `$defaultPrefix`!",
      ));
    }, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.admin))
  ];
}