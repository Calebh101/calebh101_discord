import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger_override.dart';

class ExitCode {
  const ExitCode._();

  static const int success = 0;
  static const int restart = 101;
}

late DiscordColor primaryBotColor;
late NyxxGateway client;
late Version botVersion;
bool ignoreOwner = false;

List<T> flatten<T>(List<List<T>> lists) => lists.expand((e) => e).toList();

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
  final ArgResults args;

  const BotContext({required this.client, required this.args});
}

class BotCommand {
  late Command? command;
  final Converter? Function(CommandsPlugin plugin)? converter;

  BotCommand.converter(this.converter) : command = null;

  BotCommand.command(String name, String description, Function execute, CommandAttributes attributes, {CommandOptions? options}) : converter = null {
    command = ChatCommand(name, description, id(name, execute), options: options ?? CommandOptions());
    commandAttributesMap[command!.name] = attributes;
  }

  static Map<String, CommandAttributes> commandAttributesMap = {};

  static Map<String, int> getAllCategories() {
    Map<String, int> results = {};

    for (final x in commandAttributesMap.entries) {
      results[x.value.category] = (results[x.value.category] ?? 0) + 1;
    }

    return results;
  }
}

enum BotCommandPermissions {
  any,
  admin,
  claimer,
  owner,
}

class CommandAttributes {
  final BotCommandPermissions permissionsRequired;
  final String category;
  final String? extendedDescription;

  const CommandAttributes({this.permissionsRequired = BotCommandPermissions.any, required this.category, this.extendedDescription});
}

class TerminalCommand {
  final Char key;
  final void Function() callback;

  const TerminalCommand(this.key, this.callback);
}

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
Future<BotContext?> load({required BotSettings settings, required FutureOr<Pattern> Function(MessageCreateEvent)? prefix, List<BotCommand>? Function(CommandsPlugin plugin)? commands, required List<Flag<GatewayIntents>> permissions, bool createBot = true, List<TerminalCommand> terminalCommands = const [], required DefinedUser owner, required DefinedServer? supportServer, required KVStore store, required DiscordColor primaryColor, required String botName, required Version version, required List<String> args, required ArgParser Function(ArgParser parser) argParser}) async {
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

  final token = settings.botToken.get();
  Flags<GatewayIntents> intents = Flag(0);
  final cmd = CommandsPlugin(prefix: prefix);

  for (final c in commands?.call(cmd) ?? []) {
    if (c.command != null) cmd.addCommand(c.command!);

    if (c.converter != null) {
      final x = c.converter!.call(cmd);

      if (x != null) {
        cmd.addConverter(x);
        Logger.print("Commands", "Added convertor ${x.runtimeType}");
      }
    }
  }

  for (final x in permissions) {
    intents = intents | x;
  }

  if (token == null) {
    Logger.warn("load", "No token provided!");
    return null;
  }

  client = await Nyxx.connectGateway(
    token, intents,
    options: GatewayClientOptions(plugins: [cliIntegration, cmd]),
  );

  Future<User?> user() async {
    try {
      return await client.user.get();
    } catch (_) {
      return null;
    }
  }

  cmd.onCommandError.listen((e) async {
    if (e is CommandNotFoundException) return;
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

  client.onMessageCreate.listen((event) async {
    final u = await user();

    if (u != null && event.message.content.trim() == "<@${u.id}>") {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final message = randomPingPhrase(pingPhrases, event);

      event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "$message\n-# Latency: ${formatLatency(latency)} (Real: ${formatLatency(realLatency)})"));
    }
  });

  late List<StreamSubscription<ProcessSignal>> subscriptions;

  void onClose(ProcessSignal? signal) {
    Logger.print("onClose", "Received ${signal?.name ?? "generic signal"}, closing...");
    stdin.echoMode = true;
    stdin.lineMode = true;

    for (var x in subscriptions) {
      x.cancel();
    }
  }

  final tcmd = [...[
    TerminalCommand(Char.from("q"), () async {
      try {
        Logger.print("Close", "Closing client...");
        await client.close();
      } catch (e) {
        Logger.warn("Close", "Unable to close client: $e");
      }

      onClose(null);
      exit(ExitCode.success);
    }),
    TerminalCommand(Char.from("p"), () async {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final gatewayLatency = client.gateway.latency;

      Logger.print("Ping", "HTTP latency: ${formatLatency(latency)}\nReal latency: ${formatLatency(realLatency)}\nGateway latency: ${formatLatency(gatewayLatency)}");
    }),
    TerminalCommand(Char.from("r"), () async {
      try {
        Logger.print("Restart", "Restarting...");
        await client.close();
      } catch (e) {
        Logger.warn("Restart", "Unable to close client: $e");
      }

      onClose(null);
      exit(ExitCode.restart);
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
  return BotContext(client: client, args: results);
}

FutureOr<String?> memberToString(Member? member, {bool detailed = false}) async {
  if (member == null) return null;
  final user = member.user ?? await client.users[member.id].get();

  try {
    return [
      "**${member.nick ?? user.globalName ?? user.username}**",
      "(*${user.username}*)",
      if (detailed) "(`${member.id}`)",
    ].join(" ");
  } catch (e) {
    Logger.print("memberToString", "$e (member=${member.runtimeType}, user=${member.user.runtimeType}, nick=${member.nick}, id=${member.id}, detailed=$detailed)");
    return userToString(user);
  }
}

FutureOr<String?> userToString(User? user, {bool detailed = false}) async {
  if (user == null) return null;

  try {
    return [
      "**${user.globalName ?? user.username}** (*${user.username}*)",
      if (detailed) "(`${user.id}`)",
    ].join(" ");
  } catch (_) {
    return null;
  }
}

FutureOr<String> userOrMemberToString(Member? member, User user, {bool detailed = false}) async {
  return await memberToString(member, detailed: detailed) ?? await userToString(user, detailed: detailed) ?? "`${user.id}`";
}

String? roleToString(Role? role) {
  if (role == null) return null;
  return "**${role.name}**";
}

String formatLatency(Duration latency) {
  return "${(latency.inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(3)}ms";
}

Future<DiscordColor?> getPrimaryColor(Member? member) async {
  if (member == null) return null;
  final roles = await Future.wait(member.roles.map((id) => id.get()));
  final colored = roles.where((r) => r.colors.primary.value != 0).toList();
  if (colored.isEmpty) return null;
  colored.sort((a, b) => b.position.compareTo(a.position));
  return colored.first.colors.primary;
}

extension ToMention on int {
  String toMention() {
    return "<@$this>";
  }

  String toRoleMention() {
    return "<@&$this>";
  }

  String toChannel() {
    return "<#$this>";
  }
}

extension RoleToMention on Role {
  String toMention() {
    return this.id.value.toRoleMention();
  }
}

extension UserToMention on User {
  String toMention() {
    return this.id.value.toMention();
  }
}

extension MemberToMention on Member {
  String toMention() {
    return this.id.value.toMention();
  }
}

extension ChannelToMention on Channel {
  String toMention() {
    return this.id.value.toChannel();
  }
}

extension ToDiscordCodeBlock on Object? {
  String toDiscordCodeBlock({String? language}) {
    return "```${language ?? ""}\n$this\n```";
  }

  String toDiscordCodeString() {
    return "`$this`";
  }
}

extension DiscordTimestamp on DateTime {
  String toDiscordTimestamp([String? flag]) {
    return "<t:${((toUtc().millisecondsSinceEpoch) / Duration.millisecondsPerSecond).floor()}${flag != null ? ":$flag" : ""}>";
  }

  /// Short time (e.g. `9:30 AM`)
  static const String shortTime = 't';

  /// Long time (e.g. `9:30:00 AM`)
  static const String longTime = 'T';

  /// Short date (e.g. `03/24/2026`)
  static const String shortDate = 'd';

  /// Long date (e.g. `March 24, 2026`)
  static const String longDate = 'D';

  /// Short date and time — default (e.g. `March 24, 2026 9:30 AM`)
  static const String shortDateTime = 'f';

  /// Long date and time (e.g. `Tuesday, March 24, 2026 9:30 AM`)
  static const String longDateTime = 'F';

  /// Relative time (e.g. `in 5 minutes` / `3 hours ago`)
  static const String relative = 'R';
}

extension ContextHelper on ChatContext {
  void respondWithError(String message, {ResponseLevel? level}) async {
    try {
      await respond(MessageBuilder(content: message), level: level);
    } catch (e) {
      Logger.warn("ChatContext.respondWithError", "Unable to respond with error '$message': $e");
    }
  }

  bool verifyPerms(BotCommandPermissions perms, ServerSettings? settings) {
    switch (perms) {
      case BotCommandPermissions.any: return true;
      case BotCommandPermissions.admin: return isAdmin(settings: settings!, id: user.id);
      case BotCommandPermissions.claimer: return isClaimer(settings: settings!, id: user.id);
      case BotCommandPermissions.owner: return isOwner(id: user.id);
    }
  }

  Future<bool> assurePerms(BotCommandPermissions perms, ServerSettings settings) async {
    final result = verifyPerms(perms, settings);

    if (result == false) {
      await respond(MessageBuilder(content: "You don't have the required permissions to access this command.\n-# Permissions required: `${perms.name}`"));
      return false;
    }

    return true;
  }

  Future<bool> assureOwner() async {
    final result = verifyPerms(BotCommandPermissions.owner, null);

    if (result == false) {
      await respond(MessageBuilder(content: "You don't have the required permissions to access this command.\n-# Permissions required: `${BotCommandPermissions.owner.name}`"));
      return false;
    }

    return true;
  }

  FutureOr<String?> userString({bool detailed = false}) async => userOrMemberToString(member, user, detailed: detailed);

  Future<Message> updateMessage(Message message, MessageUpdateBuilder builder) async {
    if (this is InteractionChatContext) {
      return await (this as InteractionChatContext).interaction.updateOriginalResponse(builder);
    } else {
      return await message.update(builder);
    }
  }
}

bool dev = false;

ArgParser defaultArgParser() {
  return ArgParser()
    ..addFlag("dev", help: "If the bot is in dev mode.", callback: (value) => dev = value);
}