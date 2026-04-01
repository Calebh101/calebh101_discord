import 'package:calebh101_discord/calebh101_discord.dart';

List<BotCommand> prefixCommands(ServerSettings? Function(Guild guild) getSettings) => [
  BotCommand.command("prefix", "Get/set the bot's prefix.", (ChatContext context, [String? prefix]) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");

    if (prefix == null) {
      await context.respond(MessageBuilder(
        content: "Prefix is currently set to `${settings.prefix.get() ?? defaultPrefix}`.",
      ));

      return;
    }

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
  }, CommandAttributes(category: "Bot")),
  BotCommand.command("resetprefix", "Reset the bot's prefix for this server.", (ChatContext context) async {
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