import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger/logger_override.dart';
import 'package:collection/collection.dart';

final DateTime started = DateTime.now();

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
  final ClientStore<NyxxGateway> clients;
  final KVStore store;
  final ArgResults args;

  const BotContext({required this.clients, required this.args, required this.store});
}

class TerminalCommand {
  final Char key;
  final void Function() callback;

  const TerminalCommand(this.key, this.callback);
}

late Future<Never> Function([int code]) close;

bool stdinInitialized = false;
NyxxGateway? primaryClient;

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
Future<BotContext?> load({required BotSettings settings, required FutureOr<Pattern> Function(MessageCreateEvent)? prefix, List<BotCommand>? Function<T extends ChatContext>(CommandsPlugin plugin)? commands, List<BotConverter>? Function(CommandsPlugin plugin)? converters, required List<Flag<GatewayIntents>> permissions, bool createBot = true, List<TerminalCommand> terminalCommands = const [], required List<DefinedUser> owners, required DefinedServer? supportServer, required KVStore store, required DiscordColor primaryColor, required String botName, required Version version, required List<String> args, required ArgParser Function(ArgParser parser) argParser, required Map<String, String> tokens, required PluginStore plugins}) async {
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
  globalOwners = owners;
  primaryBotColor = primaryColor;
  globalSupportServer = supportServer;

  if (!(await settings.initCore())) return null;
  if (!(await settings.init())) return null;
  loggerOverride();

  Flags<GatewayIntents> intents = Flag(0);
  List<String> existingConverters = [];
  final cmd = CommandsPlugin(prefix: prefix);

  Precheck.addPrecheck(Precheck((event) {
    final settings = BotSettings(store);
    final userId = event.getData((x) => x.user?.id ?? x.member?.id, (x) => x.message.author.id, (x) => x.user?.id ?? x.member?.id, (x) => x.user?.id ?? x.member?.id);

    if (userId == null) Logger.warn("Precheck", "User ID was null for event ${event.runtimeType}");
    return userId == null || !isIgnored(store, userId);
  }));

  Precheck.addPrecheck(Precheck((event) async {
    final settings = BotSettings(store);
    final ids = event.getData((x) => (x.guildId, x.user?.id ?? x.member?.id), (x) => (x.guildId, x.message.author.id), (x) => (x.guildId, x.user?.id ?? x.member?.id), (x) => (x.guildId, x.user?.id ?? x.member?.id));

    final blocked = settings.blockedGuilds.get().contains(ids.$1);
    final blockedOwner = settings.blockedGuildOwners.get().contains(ids.$2);

    if (blocked || blockedOwner) {
      Logger.warn("Bot", "Blocked: ${blocked ? "guild" : "0"}, ${blockedOwner ? "owner" : "0"} (ids: $ids)");
      final guild = await event.getData((x) => x.guild?.get(), (x) => x.guild?.get(), (x) => x.guild?.get(), (x) => x.guild?.get());
      if (guild == null) throw Exception("No guild.");
      await guild.leave();
      return false;
    }

    return true;
  }));

  R cr<R>(R Function<T extends ChatContext>() callback) => switch (commandType.internalType) {
    == MessageChatContext => callback.call<MessageChatContext>(),
    == InteractionChatContext => callback.call<InteractionChatContext>(),
    _ => callback.call<ChatContext>(),
  };

  final cmds = cr(<T extends ChatContext>() => commands?.call<T>(cmd) ?? []);
  cmds.addAll(await cr(<T extends ChatContext>() => plugins.commands<T>(cmd, store)));

  final cnv = converters?.call(cmd) ?? [];
  cnv.addAll(await plugins.converters(cmd, store));

  for (final c in cnv) {
    if (existingConverters.contains(c.id)) continue;
    final x = c.callback.call(cmd);

    if (x != null) {
      cmd.addConverter(x);
      existingConverters.add(c.id);
      Logger.print("Commands", "Added convertor ${x.runtimeType}");
    }
  }

  for (final c in cmds) {
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

  for (final x in BotCommand.getFromRegistry(cmd)) {
    try {
      cmd.addCommand(x);
    } catch (_) {
      Logger.warn("load", "Command: ${x.name} (${x.runtimeType})");
      rethrow;
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

  T? ifContextual<T>(Object? e, T? Function(ContextualException e) callback) {
    if (e is ContextualException) return callback.call(e);
    return null;
  }

  R? ifIs<R, T>(Object? o, R Function(T o) c, {R? Function(dynamic o)? otherwise}) {
    if (o is T) return c.call(o);
    return otherwise?.call(o);
  }

  onCommandError = ((e) async {
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
        if (showHelp) "Run `${settings.prefix.get()}help ${context.command.name}` for more info.",
      ].join("\n"));
    }

    if (e is ConverterFailedException) {
      return handleError(e, "Invalid command input.", codeblock: "Could not parse input to type ${e.failed}.", showHelp: true);
    } else if (e is NotEnoughArgumentsException) {
      return handleError(e, "Not enough arguments.", showHelp: true);
    } else if (e is UncaughtException) {
      if (e.message.contains("BASE_TYPE_MAX_LENGTH")) {
        return handleError(e, "The response generated was too long.");
      }
    }

    if (e is ContextualException && e.context is MessageChatContext) {
      await (e.context as MessageChatContext).respond(MessageBuilder(
        content: "An unknown error has occurred.\n```${e.runtimeType}```",
      ));
    }

    for (final o in owners) {
      onCommandErrorDm?.call(o.id, e);
    }
  });

  onCommandErrorDm = (id, e, {client}) async {
    List<Object> errors = [];
    bool success = false;
    final c = client != null ? [client] : clients.clients.values;

    for (int i = 0; i < c.length; i++) {
      final client = c.elementAt(i);

      try {
        final channel = await client.users.createDm(id);
        final context = ifContextual(e, (e) => e.context);
        final message = ifIs<Message, MessageChatContext>(context, (x) => x.message) ?? ifIs<Message?, InteractionChatContext>(context, (x) => x.interaction.message);
        final timestamp = message?.timestamp.toUtc() ?? DateTime.now().toUtc();
        final stack = (ifIs<StackTrace?, CommandsException>(e, (e) => e.stackTrace) ?? StackTrace.current).toString();

        await channel.sendMessage(MessageBuilder(embeds: [EmbedBuilder(
          title: "Unhandled Command Error",
          description: [
            "Type: ${e.runtimeType}",
            "Context: ${context.runtimeType}",
          ].join("\n").toDiscordCodeBlock(),
          fields: [
            EmbedFieldBuilder(name: "Error", value: (ifIs<String, CommandsException>(e, (e) => e.message) ?? e.toString()).toDiscordCodeBlock(), isInline: false),
            EmbedFieldBuilder(name: "Stack Trace", value: stack.substring(0, min(stack.length, 1024)).toDiscordCodeBlock(), isInline: false),
            if (context != null) EmbedFieldBuilder(name: "Where", value: [
              "Client: ${context.client.user.id.toDiscordCodeString()}",
              "Guild: ${context.guild?.id.toDiscordCodeString() ?? "none"}",
              "Channel: ${context.channel.id.toDiscordCodeString()}",
              "Message: ${message?.id.toDiscordCodeString() ?? "none"}",
              "Link: ${discordLink(context.guild?.id, context.channel.id, message?.id)}",
            ].join("\n"), isInline: false),
            if (context != null) EmbedFieldBuilder(name: "Who", value: [
              "User ID: ${context.user.id.toDiscordCodeString()}",
              "User mention: ${context.user.toMention()}",
              "User name: ${await memberFromUserToString(context.user, client: client, guild: context.guild)}",
            ].join("\n"), isInline: false),
            EmbedFieldBuilder(name: "Timestamp", value: "${timestamp.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} (${timestamp.toDiscordTimestamp(DiscordTimestamp.relative)}) (source: `${message != null ? "message" : "system"}`)", isInline: false),
            if (message != null) EmbedFieldBuilder(name: "Message", value: message.content.substring(0, min(message.content.length, 1024)), isInline: false),
          ],
          color: DiscordColor.parseHexString("#FF7F7F"),
          timestamp: timestamp,
          thumbnail: EmbedThumbnailBuilder(url: context?.member?.avatar?.url ?? context?.user.avatar.url ?? (await client.user.get()).avatar.url),
        )]));

        success = true;
        break;
      } catch (e) {
        errors.add(e);
      }
    }

    if (!success) {
      Logger.warn("onCommandErrorDm", "Unable to DM error: ${errors.join(", ")}");
    }
  };

  cmd.onCommandError.listen(onCommandError);

  clients.run((client) => client.onMessageCreate.listen((event) async {
    if (isIgnored(store, event.message.author.id)) return;
    final u = await user(event.gateway.client);

    final userWhoSentThisMessage = event.message.author is User ? event.message.author as User : null;
    final isValidUser = userWhoSentThisMessage != null && !userWhoSentThisMessage.isBot && !userWhoSentThisMessage.isSystem;
    final isSimplePing = u != null && event.message.content.trim() == "<@${u.id}>";

    final prefix = ifGuild(store, event.guildId, (id) => ServerSettings(store, id))?.prefix.get() ?? defaultPrefix;
    final isValidContent = u != null && !event.message.content.startsWith(prefix) && !event.message.content.startsWith("<@${u.id}>") && event.message.content.contains("<@${u.id}>");

    if (isValidUser && isSimplePing) {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final message = randomPingPhrase(pingPhrases, event);

      try {
        await event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "$message\n-# Latency: ${formatLatency(latency)} (Real: ${formatLatency(realLatency)})"));
      } catch (e) {
        Logger.warn("load", "Error responding to message ${event.message.id} by ${userWhoSentThisMessage.id}: $e");
      }
    } else if (isValidUser && isValidContent) {
      try {
        await event.message.react(ReactionBuilder(name: "👍", id: null));
      } catch (e) {
        Logger.warn("load", "Error reacting to message ${event.message.id} by ${userWhoSentThisMessage.id}: $e");
      }
    }
  }));

  late List<StreamSubscription<ProcessSignal>> subscriptions;

  void onClose(ProcessSignal? signal) {
    Logger.print("Close", "Received ${signal?.name ?? "generic signal"}, closing...");
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
  final context = BotContext(clients: clients, args: results, store: store);
  plugins.load(context);
  primaryClient = context.clients.clients.values.first;
  return context;
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

void wrap(void Function() callback) {
  runZonedGuarded(() {
    callback.call();
  }, (e, t) async {
    Logger.error("Main", "Error: $e (primaryClient=${primaryClient.runtimeType})", trace: t);

    if (primaryClient != null) await alertOwners(primaryClient!, EmbedBuilder(
      color: DiscordColor.parseHexString("#AA4444"),
      title: "Critical Error",
      fields: [
        EmbedFieldBuilder(name: "Type", value: e.runtimeType.toDiscordCodeString(), isInline: true),
        EmbedFieldBuilder(name: "Time", value: DateTime.now().toUtc().toDiscordTimestamp(DiscordTimestamp.shortDateTime), isInline: true),
        EmbedFieldBuilder(name: "Exception", value: e.toDiscordCodeBlock(), isInline: false),
        EmbedFieldBuilder(name: "Stack Trace", value: t.format().toDiscordCodeBlock(), isInline: false),
      ],
    ));

    exit(-1);
  });
}

Uri discordLink(Snowflake? guild, Snowflake channel, [Snowflake? message]) {
  return Uri.parse("https://discord.com/channels/${[guild ?? "@me", channel, ?message].join("/")}");
}

extension ToAnything on Object? {
  T to<T>(T x) => x;
}