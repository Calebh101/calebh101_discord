import 'package:calebh101_discord/calebh101_discord.dart';

BotCommand restartCommand() => BotCommand.command("restart", "Restart the bot.", (ChatContext context) async {
  if (await context.assureOwner() == false) return;
  await context.respond(MessageBuilder(content: "Restarting..."));
  Logger.print("Commands.Kill", "User ${context.user.id} requested my restart.");
  await close.call(ExitCode.restart);
}, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.owner));

BotCommand killCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("kill", "Kill the bot. He will be sad.", (ChatContext context) async {
  if (!isOwner(id: context.user.id)) {
    context.respondWithError("You are not the owner of me!");
    return;
  }

  await context.respond(MessageBuilder(content: "I am now dead."));
  Logger.print("Commands.Kill", "User ${context.user.id} requested my death.");
  close.call();
}, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Bot"));

BotCommand echoDebugCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("echo", "Echo the input text from the bot.", (ChatContext context, String text, [int count = 1]) async {
  if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
  final settings = getSettings.call(context.guild!);
  if (settings == null) return context.respondWithError("Unable to load settings.");
  if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

  await context.respond(MessageBuilder(
    content: text * count,
  ));
}, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug"));