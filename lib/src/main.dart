import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger/logger_override.dart';
import 'package:collection/collection.dart';

class ClientStore<T extends Nyxx> {
  Map<String, T> clients = {};
  ClientStore(this.clients);

  List<R> run<R>(R Function(T client) callback) {
    return clients.entries.map((x) => callback.call(x.value)).toList();
  }

  List<R> runIndexed<R>(R Function(int i, String key, T client) callback) {
    return clients.entries.mapIndexed((i, x) => callback.call(i, x.key, x.value)).toList();
  }
}

class ExitCode {
  const ExitCode._();

  static const int success = 0;
  static const int restart = 101;
}

late DiscordColor primaryBotColor;
late Version botVersion;
bool ignoreOwner = false;

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

bool dev = false;

ArgParser defaultArgParser() {
  return ArgParser()
    ..addFlag("dev", help: "If the bot is in dev mode.", callback: (value) => dev = value);
}

class BotContext {
  final ClientStore<NyxxGateway> client;
  final ArgResults args;

  const BotContext({required this.client, required this.args});
}

class TerminalCommand {
  final Char key;
  final void Function() callback;

  const TerminalCommand(this.key, this.callback);
}

late Future<Never> Function([int code]) close;

typedef OnStart = void Function();
late OnStart _onStart;
bool stdinInitialized = false;

set onStart(OnStart value) {
  _onStart = value;
  _onStart.call();
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
Future<BotContext?> load({required BotSettings settings, required FutureOr<Pattern> Function(MessageCreateEvent)? prefix, List<BotCommand>? Function(CommandsPlugin plugin)? commands, required List<Flag<GatewayIntents>> permissions, bool createBot = true, List<TerminalCommand> terminalCommands = const [], required DefinedUser owner, required DefinedServer? supportServer, required KVStore store, required DiscordColor primaryColor, required String botName, required Version version, required List<String> args, required ArgParser Function(ArgParser parser) argParser, required Map<String, String> tokens}) async {
  try {
    final _ = _onStart.hashCode;
  } catch (e) {
    Logger.error("load", "onStart must be initialized.\n$e");
    return null;
  }

  late ArgResults results;
  final parser = argParser.call(defaultArgParser());

  try {
    results = parser.parse(args);
  } catch (e) {
    Logger.error("load", "Unable to parse arguments: $e");
    stdout.write(parser.usage);
    return null;
  }

  botVersion = version;
  globalBotName = botName;
  globalOwner = owner;
  primaryBotColor = primaryColor;
  globalSupportServer = supportServer;

  if (!(await settings.initCore())) return null;
  if (!(await settings.init())) return null;
  loggerOverride();

  Flags<GatewayIntents> intents = Flag(0);
  final cmd = CommandsPlugin(prefix: prefix);

  for (final c in commands?.call(cmd) ?? [] as List<BotCommand>) {
    if (c.command != null) cmd.addCommand(c.command!);

    if (c.converter != null) {
      final x = c.converter!.call(cmd);

      if (x != null) {
        cmd.addConverter(x);
        Logger.print("Commands", "Added convertor ${x.runtimeType}");
      }
    }

    if (c.check != null) {
      final x = c.check!.call(cmd);

      if (x != null) {
        cmd.check(x);
        Logger.print("Commands", "Added check ${x.runtimeType}");
      }
    }
  }

  for (final x in permissions) {
    intents = intents | x;
  }

  if (tokens.isEmpty) {
    Logger.warn("load", "No tokens provided!");
    return null;
  }

  ClientStore<NyxxGateway> clients = ClientStore(Map.fromEntries(await Future.wait(
    tokens.entries.map((token) async {
      Logger.print("main", "Loading client ${token.key}...");

      return MapEntry(token.key, await Nyxx.connectGateway(
        token.value, intents,
        options: GatewayClientOptions(
          plugins: [cliIntegration, cmd],
        ),
      ));
    }),
  )));

  Future<User?> user(NyxxGateway client) async {
    try {
      return await client.user.get();
    } catch (_) {
      return null;
    }
  }

  cmd.onCommandError.listen((e) async {
    if (e is CommandNotFoundException || e is CheckFailedException) return;
    Logger.warn("Commands", "Command error: $e (error: ${e.runtimeType}, context: ${e is ContextualException ? e.context.runtimeType : null})", trace: e.stackTrace);

    void handleError<T extends ContextualException>(T e, String message, {String? codeblock, String? codeblocklang, bool showHelp = false}) {
      if (e.context is! MessageChatContext) return;
      final context = e.context as MessageChatContext;
      if (context.guild == null) return;
      final settings = ServerSettings(store, context.guild!.id);

      context.respondWithError([
        message,
        if (codeblock != null) "```$codeblocklang\n$codeblock\n```",
        if (showHelp) "Run `${settings.prefix.get() ?? defaultPrefix}help ${context.command.name}` for more info.",
      ].join("\n"));
    }

    if (e is ConverterFailedException) {
      return handleError(e, "Invalid command input.", codeblock: "Could not parse input to type ${e.failed}.", showHelp: true);
    } else if (e is NotEnoughArgumentsException) {
      return handleError(e, "Not enough arguments.", showHelp: true);
    }

    if (e is ContextualException && e.context is MessageChatContext) {
      await (e.context as MessageChatContext).respond(MessageBuilder(
        content: "An unknown error has occurred.\n```${e.runtimeType}```",
      ));
    }
  });

  clients.run((client) => client.onMessageCreate.listen((event) async {
    final u = await user(event.gateway.client);

    if (u != null && event.message.content.trim() == "<@${u.id}>") {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final message = randomPingPhrase(pingPhrases, event);

      event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "$message\n-# Latency: ${formatLatency(latency)} (Real: ${formatLatency(realLatency)})"));
    }
  }));

  late List<StreamSubscription<ProcessSignal>> subscriptions;

  void onClose(ProcessSignal? signal) {
    Logger.print("onClose", "Received ${signal?.name ?? "generic signal"}, closing...");
    stdin.echoMode = true;
    stdin.lineMode = true;

    for (var x in subscriptions) {
      x.cancel();
    }
  }

  close = ([int code = ExitCode.success]) async {
    try {
      Logger.print("Close", "Closing client...");
      await Future.wait(clients.run((client) => client.close()));
    } catch (e) {
      Logger.warn("Close", "Unable to close client: $e");
    }

    onClose(null);
    exit(code);
  };

  final tcmd = [...[
    TerminalCommand(Char.from("q"), () async {
      await close();
    }),
    TerminalCommand(Char.from("p"), () async {
      clients.runIndexed((i, k, client) {
        final latency = client.httpHandler.latency;
        final realLatency = client.httpHandler.realLatency;
        final gatewayLatency = client.gateway.latency;

        Logger.print("Ping", "${i + 1}. HTTP latency: ${formatLatency(latency)}\n${i + 1}. Real latency: ${formatLatency(realLatency)}\n${i + 1}. Gateway latency: ${formatLatency(gatewayLatency)}");
      });
    }),
    TerminalCommand(Char.from("r"), () async {
      await close.call(ExitCode.restart);
    }),
    TerminalCommand(Char.from("s"), () async {
      final status = await getStatus();
      if (status != null) Logger.print("Status", status);
    }),
  ], ...terminalCommands];

  stdin.echoMode = false;
  stdin.lineMode = false;

  subscriptions = [
    ProcessSignal.sigint.watch().listen(onClose),
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onClose),
  ];

  if (!stdinInitialized) {
    stdin.listen((List<int> data) {
      for (final x in tcmd) {
        if (x.key.code == data[0]) {
          x.callback.call();
        }
      }
    });
  }

  stdinInitialized = true;
  return BotContext(client: clients, args: results);
}

Future<DiscordColor?> getPrimaryColor(Member? member) async {
  if (member == null) return null;
  final roles = await Future.wait(member.roles.map((id) => id.get()));
  final colored = roles.where((r) => r.colors.primary.value != 0).toList();
  if (colored.isEmpty) return null;
  colored.sort((a, b) => b.position.compareTo(a.position));
  return colored.first.colors.primary;
}

Future<String?> getStatus() async {
  try {
    final result = await Process.run("dev_status", [pid.toString()]);
    final output = result.stdout.toString().trim();
    if (output.trim().isEmpty) throw Exception("Output was empty: '$output'");
    return output;
  } catch (e) {
    Logger.warn("Status", "Unable to get status: $e\nMake sure the dev_status command is set up on your system.");
    return null;
  }
}