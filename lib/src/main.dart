import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger_override.dart';
import 'package:localpkg/classes.dart';

String randomPingPhrase(Map<String? Function(MessageCreateEvent event), num> phrases, MessageCreateEvent event) {
  while (true) {
    final total = phrases.values.reduce((a, b) => a + b);
    final random = Random().nextDouble() * total;
    num cumulative = 0;

    for (final entry in phrases.entries) {
      cumulative += entry.value;

      if (random < cumulative) {
        final result = entry.key(event);
        if (result != null) return result;
        break;
      }
    }
  }
}

class BotContext {
  final NyxxGateway client;
  final User? bot;

  const BotContext({required this.client, required this.bot});
}

class BotCommand {
  final Command? command;
  final Converter? converter;

  const BotCommand.command(this.command) : converter = null;
  const BotCommand.converter(this.converter) : command = null;
}

class TerminalCommand {
  final Char key;
  final void Function() callback;

  const TerminalCommand(this.key, this.callback);
}

/// Create a new gateway and bot.
///
/// [settings] is a [BotSettings] object. To use the default settings, just input `BotSettings()`. However, you can extend [BotSettings] and add your own fields.
///
/// [prefix] is the message prefix. If this has a value, you will be able to either mention the bot, or use the specific prefix in your message. Otherwise, only slash commands will be available.
///
/// [commands] is a list of [Command] objects. These will be registered as slash commands and optionally able to be used with prefixes.
///
/// [permissions] is a list of permissions. For bot apps, you should start out with `[...GatewayIntents.allUnprivileged, GatewayIntents.messageContent]`.
///
/// [createBot] will create a bot user using `client.user.get()` if true.
Future<BotContext?> load({required BotSettings settings, required FutureOr<Pattern> Function(MessageCreateEvent)? prefix, List<BotCommand>? commands, required List<Flag<GatewayIntents>> permissions, bool createBot = true, List<TerminalCommand> terminalCommands = const []}) async {
  if (!(await settings.initCore())) return null;
  if (!(await settings.init())) return null;
  loggerOverride();

  final token = await settings.botToken.getAsync();
  Flags<GatewayIntents> intents = Flag(0);
  final cmd = CommandsPlugin(prefix: prefix);

  cmd.onCommandError.listen((error) {
    if (error is CommandNotFoundException) return;
    Logger.warn("Commands", "Error type: ${error.runtimeType}, error: $error", trace: error.stackTrace);
  });

  for (final c in [...[
    BotCommand.command(ChatCommand(
      "ping", "Pong!",
      (ChatContext context) async {
        final latency = context.client.httpHandler.latency;
        final realLatency = context.client.httpHandler.realLatency;
        final gatewayLatency = context.client.gateway.latency;

        await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\n\nHTTP latency: ${formatLatency(latency)}\nReal latency: ${formatLatency(realLatency)}\nGateway latency: ${formatLatency(gatewayLatency)}"));
      },
    )),
  ], if (commands != null) ...commands]) {
    if (c.command != null) cmd.addCommand(c.command!);
    if (c.converter != null) cmd.addConverter(c.converter!);
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

  final user = createBot ? await client.user.get() : null;

  client.onMessageCreate.listen((event) async {
    if (user != null && event.message.content.trim() == "<@${user.id}>") {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final message = randomPingPhrase(pingPhrases, event);

      event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "$message\n-# Latency: ${formatLatency(latency)} (Real: ${formatLatency(realLatency)})"));
    }
  });

  final tcmd = [...[
    TerminalCommand(Char.from("q"), () async {
      Process.killPid(pid, ProcessSignal.sigint);
    }),
    TerminalCommand(Char.from("p"), () async {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final gatewayLatency = client.gateway.latency;

      Logger.print("Ping", "HTTP latency: ${formatLatency(latency)}\nReal latency: ${formatLatency(realLatency)}\nGateway latency: ${formatLatency(gatewayLatency)}");
    }),
  ], ...terminalCommands];

  stdin.echoMode = false;
  stdin.lineMode = false;

  late List<StreamSubscription<ProcessSignal>> subscriptions;

  void onClose(ProcessSignal signal) {
    Logger.print("onClose", "Received ${signal.name}, closing...");
    stdin.echoMode = true;
    stdin.lineMode = true;

    for (var x in subscriptions) {
      x.cancel();
    }
  }

  subscriptions = [
    ProcessSignal.sigint.watch().listen(onClose),
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onClose),
  ];

  stdin.listen((List<int> data) {
    for (final x in tcmd) {
      if (x.key.code == data[0]) {
        x.callback.call();
      }
    }
  });

  return BotContext(client: client, bot: user);
}

String? memberToString(Member? member) {
  if (member == null) return null;

  try {
    return "**${member.nick ?? member.user?.globalName ?? member.user?.username ?? (throw UnimplementedError("Couldn't find a valid name for member."))}** (*${member.user?.username ?? (throw UnimplementedError("Couldn't find a valid username for member."))}*)";
  } catch (_) {
    return null;
  }
}

String? userToString(User? user) {
  if (user == null) return null;

  try {
    return "**${user.globalName ?? user.username}** (*${user.username}*)";
  } catch (_) {
    return null;
  }
}

String formatLatency(Duration latency) {
  return "${(latency.inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(3)}ms";
}