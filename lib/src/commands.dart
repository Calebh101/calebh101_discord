import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

RuntimeType<ChatContext> _commandType = RuntimeType<ChatContext>();
RuntimeType<ChatContext> get commandType => _commandType;

class BotCommandOptions {
  /// Whether to automatically acknowledge interactions before they expire.
  ///
  /// Sometimes, commands can take longer to complete than expected. However, Discord interactions
  /// have a 3 second timeout after receiving them, so nyxx_commands provides an automatic way to
  /// acknowledge these interactions to extend that limit to 15 minutes if your command does not
  /// respond fast enough.
  ///
  /// Setting this to false means that you must acknowledge the interaction yourself.
  ///
  /// You might also be interested in:
  /// - [autoAcknowledgeDuration], for setting the time after which interactions will be
  ///   acknowledged.
  /// - [InteractionInteractiveContext.acknowledge], for manually acknowledging interactions.
  final bool? autoAcknowledgeInteractions;

  /// The duration after which to automatically acknowledge interactions.
  ///
  /// Has no effect if [autoAcknowledgeInteractions] is `false`.
  ///
  /// If this is `null`, the timeout for interactions is calculated based on the bot's latency. On
  /// unstable networks, this might result in some interactions not being acknowledged, in which
  /// case setting this option might help.
  final Duration? autoAcknowledgeDuration;

  /// Whether to accept messages sent by bot accounts as possible commands.
  ///
  /// If this is set to false, then other bot users will not be able to execute commands from this
  /// bot. If set to true, messages sent by other bots will be parsed anc checked for commands like
  /// other messages sent by actual users.
  ///
  /// You might also be interested in:
  /// - [acceptSelfCommands], for this same setting but for the current client.
  final bool? acceptBotCommands;

  /// Whether to accept messages sent by the bot itself as possible commands.
  ///
  /// [acceptBotCommands] must also be set to `true` for this setting to allow the current bot to
  /// execute its own commands. If this is set to false, messages sent by the bot itself are not
  /// checked for commands. If it is true, messages sent by the bot itself will be checked for
  /// commands like other messages sent by actual users.
  ///
  /// Care should be taken when setting this to `true` as it can potentially result in infinite
  /// command loops.
  final bool? acceptSelfCommands;

  /// The [ResponseLevel] to use in commands if not explicit.
  ///
  /// Defaults to [ResponseLevel.public].
  final ResponseLevel? defaultResponseLevel;

  /// The type of [ChatCommand]s that are children of this entity.
  ///
  /// The type of a [ChatCommand] influences how it can be invoked and can be used to make chat
  /// commands executable only through Slash Commands, or only through text messages.
  CommandType? type;

  /// Whether command fetching should be case insensitive.
  ///
  /// If this is `true`, [ChatCommand]s may be invoked by users without the command name matching
  /// the case of the input.
  ///
  /// You might also be interested in:
  /// - [ChatCommandComponent.aliases], for invoking a single command from multiple names.
  final bool? caseInsensitiveCommands;

  BotCommandOptions({this.acceptBotCommands, this.acceptSelfCommands, this.autoAcknowledgeDuration, this.autoAcknowledgeInteractions, this.caseInsensitiveCommands, this.defaultResponseLevel, this.type}) {
    type ??= switch (commandType.internalType) {
      == MessageChatContext => CommandType.textOnly,
      == InteractionCommandContext => CommandType.slashOnly,
      _ => CommandType.all,
    };
  }

  CommandOptions toOptions() {
    return CommandOptions(acceptBotCommands: acceptBotCommands, acceptSelfCommands: acceptSelfCommands, autoAcknowledgeDuration: autoAcknowledgeDuration, autoAcknowledgeInteractions: autoAcknowledgeInteractions, defaultResponseLevel: defaultResponseLevel, caseInsensitiveCommands: caseInsensitiveCommands, type: type);
  }
}

class BotCommand<T extends Function> {
  Converter? Function(CommandsPlugin plugin)? converter;
  Check? Function(CommandsPlugin plugin)? check;
  ChatCommand? command;

  late String name;
  late final List<String>? aliases;
  late final String category;
  late final String description;
  late final T execute;
  late BotCommandPermissions permissionsRequired;
  late final bool enforcePermissions;
  late final bool noGroup;
  late final bool needsGuild;
  late final bool triggerTyping;
  late String group;
  String? extendedDescription;

  BotCommand(this.name, this.category, this.description, this.execute, {this.permissionsRequired = BotCommandPermissions.any, this.extendedDescription, this.enforcePermissions = true, this.noGroup = false, this.aliases, BotCommandOptions? options, this.group = "", this.needsGuild = false, this.triggerTyping = true}) {
    final wrappedExecute = (MessageChatContext context, List<dynamic> args) async {
      await Function.apply(execute, [context, ...args]);
    };

    if (group.trim().isEmpty) group = category.toLowerCase();
    //if (dev) group = "dev_$group";

    commandRegistry[name] = this;
    //if (dev && (noGroup || !useGroups)) name = "dev_$name";
    final o = options ?? BotCommandOptions();
    command = ChatCommand(name, description, execute, options: o.toOptions(), aliases: aliases ?? []);
  }

  @Deprecated("Use BotConverter instead.")
  BotCommand.converter(this.converter);
  BotCommand.check(this.check);

  List<String> getNames() {
    return [name, ...?aliases];
  }

  @Deprecated("Use the unnamed constructor instead.")
  factory BotCommand.command(String name, String description, T execute, CommandAttributes attributes, {CommandOptions? options, String group = "", bool noGroup = false}) {
    return BotCommand(name, attributes.category, description, execute, extendedDescription: attributes.extendedDescription, permissionsRequired: attributes.permissionsRequired, enforcePermissions: false, group: group, noGroup: noGroup);
  }

  static set commandType(CommandType type) {
    _commandType = switch (type) {
      CommandType.all => RuntimeType<ChatContext>(),
      CommandType.slashOnly => RuntimeType<InteractionChatContext>(),
      CommandType.textOnly => RuntimeType<MessageChatContext>(),
    };

    Logger.print("Commands", "Command type will now be of type $type ($_commandType)");
  }

  ChatCommand getCommandUnsafe(CommandsPlugin plugin) {
    return command!;
  }

  BotConverter getConverterUnsafe(String id) {
    return BotConverter(id, converter!);
  }

  static Map<String, BotCommand> commandRegistry = {};
  static bool useGroups = true;

  static void disableGroups() {
    useGroups = false;
  }

  static List<CommandRegisterable<CommandContext>> getFromRegistry<T extends ChatContext>(CommandsPlugin plugin) {
    if (useGroups == false) return commandRegistry.values.map((x) => x.getCommandUnsafe(plugin)).toList();
    Map<String, List<BotCommand>> groups = {};
    List<ChatGroup> results = [];
    List<ChatCommand> noGroupCommands = [];

    for (final command in commandRegistry.values) {
      if (command.noGroup) {
        noGroupCommands.add(command.getCommandUnsafe(plugin));
        continue;
      }

      final current = groups[command.group] ?? [];
      current.add(command);
      groups[command.group] = current;
    }

    for (final group in groups.entries) {
      results.add(ChatGroup(group.key, "${group.value.length} commands", children: group.value.map((x) => x.getCommandUnsafe(plugin))));
    }

    final value = [...noGroupCommands, ...results];
    Logger.print("Commands", "Found ${value.length} registerable command items (${results.length} groups, ${noGroupCommands.length} solo commands)");
    return value;
  }

  static Map<String, int> getAllCategories() {
    Map<String, int> results = {};

    for (final x in commandRegistry.entries) {
      results[x.value.category] = (results[x.value.category] ?? 0) + 1;
    }

    return results;
  }

  static BotCommand? getCommand(String name) {
    return commandRegistry.entries.firstWhereOrNull((x) => x.key == name || (x.value.aliases ?? []).any((x) => x == name))?.value;
  }
}

class BotConverter<T> {
  final String id;
  final Converter<T>? Function(CommandsPlugin plugin) callback;

  const BotConverter(this.id, this.callback);

  BotCommand toBotCommand() {
    return BotCommand.converter(callback);
  }

  @override
  String toString() {
    return "BotConverter($id, $T)";
  }
}

enum BotCommandPermissions {
  any,
  mod,
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

BotCommand defaultCheck(KVStore store) => BotCommand.check((plugin) {
  return Check((context) async {
    if (isIgnored(store, context.user.id)) return false;
    final command = BotCommand.getCommand(context.command.name/*.replaceFirst("dev_", "")*/);

    if (command == null) {
      Logger.error("Check", "Invalid command: ${context.command.name}");
      return false;
    }

    final override = RestrictCommandsPlugin.getOverrideDefaultPermissions(store: store, command: command.name, guildId: context.guild?.id);

    if (command.enforcePermissions && override != null) {
      if (command.permissionsRequired == BotCommandPermissions.owner) {
        if (await context.assureOwner() == false) return false;
      } else if (command.permissionsRequired != BotCommandPermissions.any) {
        if (await context.assureGuild() == false) return false;
        final settings = ServerSettings(store, context.guild!.id);
        if (await context.assurePerms(command.permissionsRequired, settings) == false) return false;
      }
    }

    final restrictPass = await RestrictCommandsPlugin.check(client: context.client, command: command.name, store: store, guild: context.guild, userId: context.user.id, channelId: context.channel.id);
    final pass = restrictPass != null;

    if (!pass) {
      if (context is MessageChatContext) await context.message.react(ReactionBuilder(name: "🚫", id: null));
      if (context is InteractionChatContext) await context.respond(MessageBuilder(content: "Command is disabled.\nRun `checkcommand \"${command.name}\"` to learn more."), level: ResponseLevel.hint);
      return false;
    }

    if (command.needsGuild) {
      if (await context.assureGuild() == false) return false;
    }

    if (command.triggerTyping) await context.channel.triggerTyping();
    return true;
  });
});

bool isIgnored(KVStore store, Snowflake id) {
  return (BotSettings(store).ignored.get() ?? []).any((x) => x == id);
}

List<BotCommand> botSettingToCommands<T>(SettingsObject<T> setting, {required String name, required String category, required String description, String Function(T? input)? toReadable, bool requiresOwnerForGet = true, bool private = false}) {
  return [
    BotCommand("set$name", category, "Set setting $name: $description", (ChatContext context, GreedyString input) async {
      final converter = context.commands.getConverter(RuntimeType<T>());
      final value = await converter?.convert(StringView(input.data), context);

      if (value == null) {
        await context.respond(MessageBuilder(content: "No converter found or converting failed for type `$T`.\n```${converter.runtimeType.toDiscordCodeBlock()}"));
        return;
      }

      setting.set(value);
      await context.respond(MessageBuilder(content: "Set setting `$name`."), level: private ? ResponseLevel.hint : ResponseLevel.public);
    }, permissionsRequired: BotCommandPermissions.owner),
    BotCommand("get$name", category, "Get setting $name: $description", (ChatContext context) async {
      final value = setting.get();
      final hasPerms = !requiresOwnerForGet || isOwner(id: context.user.id);

      toReadable ??= (input) {
        return input?.toString() ?? "Not set.";
      };

      await context.respond(MessageBuilder(content: "**Bot Setting `$name`**:\n$description${hasPerms ? "\n\n${toReadable!.call(value)}" : ""}"), level: private ? ResponseLevel.private : ResponseLevel.public);
    }),
  ];
}