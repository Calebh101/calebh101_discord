import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger_override.dart';

/// Equal to [print].
final _print = print;

class Logger {
  static void log(String input) {
    _print(input);
  }

  static void print(String module, Object? input) {
    log("LOG [$module] $input");
  }

  static void warn(String module, Object? input, {StackTrace? trace}) {
    log("WRN [$module] $input${trace != null ? "\n$trace" : ""}");
  }

  static void error(String module, Object? input, {StackTrace? trace}) {
    log("ERR [$module] $input${trace != null ? "\n$trace" : ""}");
  }
}

class BotResult {
  final NyxxGateway client;
  final User bot;

  const BotResult({required this.client, required this.bot});
}

Future<BotResult?> load({required BotSettings settings, String prefix = "!", List<Command>? commands, required List<GatewayIntents> permissions}) async {
  if (!(await settings.initCore())) return null;
  if (!(await settings.init())) return null;
  loggerOverride();

  final token = await settings.botToken.getAsync();
  Flags<GatewayIntents> intents = GatewayIntents.allUnprivileged | GatewayIntents.messageContent;
  final cmd = CommandsPlugin(prefix: mentionOr((_) => prefix));

  cmd.onCommandError.listen((error) {
    if (error is CommandNotFoundException) return;
    Logger.warn("Commands", "Error type: ${error.runtimeType}, error: $error", trace: error.stackTrace);
  });

  for (final c in [...[
    ChatCommand(
      "ping", "Pong!",
      (ChatContext context) async {
        final latency = context.client.httpHandler.latency;
        await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\nLatency: ${(latency.inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(3)}ms"));
      },
    ),
  ], if (commands != null) ...commands]) {
    cmd.addCommand(c);
  }

  for (final x in permissions) {
    intents = intents | x;
  }

  if (token == null) {
    Logger.warn("load", "No token provided!");
    return null;
  }

  final client = await Nyxx.connectGateway(
    token, intents,
    options: GatewayClientOptions(plugins: [cliIntegration, cmd]),
  );

  final user = await client.user.get();

  client.onMessageCreate.listen((event) async {
    if (event.message.content.trim() == "<@${user.id}>") {
      event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "WHAT'S ALL THAT NOISE??"));
    }
  });

  return BotResult(client: client, bot: user);
}