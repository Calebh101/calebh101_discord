import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class BotManagePlugin extends BotPlugin {
  BotManagePlugin() : super(id: "botmanage", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [restartCommand(), killCommand(), echoDebugCommand(store)];
  }

  BotCommand restartCommand() => BotCommand.command("restart", "Restart the bot.", (ChatContext context) async {
    if (await context.assureOwner() == false) return;
    await context.respond(MessageBuilder(content: "Restarting..."));
    Logger.print("Commands.Kill", "User ${context.user.id} requested my restart.");
    await close.call(ExitCode.restart);
  }, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.owner));

  BotCommand killCommand() => BotCommand.command("kill", "Kill the bot. He will be sad.", (ChatContext context) async {
    if (!isOwner(id: context.user.id)) {
      context.respondWithError("You are not the owner of me!");
      return;
    }

    await context.respond(MessageBuilder(content: "I am now dead."));
    Logger.print("Commands.Kill", "User ${context.user.id} requested my death.");
    close.call();
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Bot"));

  BotCommand echoDebugCommand(KVStore store) => BotCommand.command("echo", "Echo the input text from the bot.", (ChatContext context, String text, [int count = 1]) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = ServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

    await context.respond(MessageBuilder(
      content: text * count,
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug"));
}