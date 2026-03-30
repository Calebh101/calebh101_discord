import 'package:calebh101_discord/calebh101_discord.dart';

List<BotCommand> ignoreCommands(KVStore store) => [
  BotCommand("ignore", "Admin", "Ignore a user", (ChatContext context, User user) async {
    if (isOwner(id: user.id)) return context.respondWithError("The owner of the bot cannot be ignored.");
    final settings = BotSettings(store);
    final current = settings.ignored.get() ?? [];

    if (isIgnored(store, user.id)) return context.respondWithError("User is already ignored.");
    current.add(user.id);
    settings.ignored.set(current);
    await context.respond(MessageBuilder(content: "${await userToString(user)} has been **ignored**."));
  }, permissionsRequired: BotCommandPermissions.owner),
  BotCommand("unignore", "Admin", "Ignore a user", (ChatContext context, User user) async {
    final settings = BotSettings(store);
    final current = settings.ignored.get() ?? [];

    if (!isIgnored(store, user.id)) return context.respondWithError("User is already not ignored.");
    current.remove(user.id);
    settings.ignored.set(current);
    await context.respond(MessageBuilder(content: "${await userToString(user)} has been **unignored**."));
  }, permissionsRequired: BotCommandPermissions.owner),
  BotCommand("ignored", "Admin", "Ignore a user", (ChatContext context, User user) async {
    final settings = BotSettings(store);
    final current = settings.ignored.get() ?? [];
    await context.respond(MessageBuilder(content: "${await userToString(user)} is currently ${isIgnored(store, user.id) ? "**ignored**" : "**not** ignored"}."));
  }),
];