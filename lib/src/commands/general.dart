import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:system_info/system_info.dart';

BotCommand messageMe() => BotCommand.command("messageme", "DM me.", (ChatContext context) async {
  bool dmSuccessful = false;

  try {
    (await context.client.users.createDm(context.user.id)).sendMessage(MessageBuilder(
      content: "Hey there, <@${context.user.id}>!",
    ));

    dmSuccessful = true;
  } catch (e) {
    Logger.warn("Commands.Suggestion.Deny", "Unable to open DM: $e");
  }

  await context.respond(MessageBuilder(content: dmSuccessful ? "<@${context.user.id}>, I have DMed you." : "<@${context.user.id}>, I was **not** able to DM you."), level: ResponseLevel.hint);
}, CommandAttributes(category: "Bot"));

BotCommand aboutCommand(KVStore? store) => BotCommand.command("about", "See stats about this bot.", (ChatContext context) async {
  final settings = store != null && context.guild != null ? ServerSettings(store, context.guild!.id) : null;
  final prefix = settings?.prefix.get() ?? "!";

  await context.respond(MessageBuilder(
    content: [
      "**$globalBotName**: A bot that does something",
      "Version $botVersion by [Calebh101](<https://github.com/Calebh101>)",
      null,
      "Current prefix: `$prefix`",
      "To see all commands, run `${prefix}help`.",
      null,
      [
        "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion}".trim(),
        (() {
          final processor = SysInfo.processors.first;
          return "${processor.vendor} ${processor.name}".trim();
        }()),
      ].join("\n").trim().toDiscordCodeBlock(),
      null,
      "Built with [nyxx](<https://pub.dev/packages/nyxx>), running on Dart:",
      Platform.version.trim().toDiscordCodeBlock(),
      if (globalSupportServer != null) ...["For support: ${globalSupportServer!.invite}"],
    ].map((x) => x ?? "").join("\n"),
  ));
}, CommandAttributes(category: "Bot"));

BotCommand pingCommand() => BotCommand.command(
  "ping", "Pong!",
  (ChatContext context) async {
    final latency = context.client.httpHandler.latency;
    final realLatency = context.client.httpHandler.realLatency;
    final gatewayLatency = context.client.gateway.latency;

    final Map<String, String> keys = {
      "HTTP latency": formatLatency(latency),
      "Real latency": formatLatency(realLatency),
      if (gatewayLatency.inMicroseconds > 0) "Gateway latency": formatLatency(gatewayLatency),
    };

    await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\n\n${keys.entries.map((x) {
      return "> ${x.key}: **${x.value}**";
    }).join("\n")}"));
  },
  CommandAttributes(category: "Bot"),
);

BotCommand listAllServerSettings(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("allsettings", "List all settings for this server. Admin only.", (ChatContext context) async {
  if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
  final settings = getSettings.call(context.guild!);
  if (settings == null) return context.respondWithError("Unable to load settings.");
  if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
  final all = settings.getAll().entries;

  context.respond(MessageBuilder(
    content: "All settings for *${context.guild?.name}*:\n${all.map((x) => "- `${x.key}`: `${x.value}`").join("\n")}",
  ), level: ResponseLevel.private);
}, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server"));

BotCommand statusCommand() => BotCommand("status", "Bot", "See the bot's status.", (ChatContext context) async {
  final m = await context.respond(MessageBuilder(content: "Fetching status..."));
  final status = await getStatus();

  Logger.print("Status", "Bot status: $status");
  await context.updateMessage(m, MessageUpdateBuilder(content: status?.toDiscordCodeBlock() ?? "No status found."));
});