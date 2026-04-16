import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class BotCommand {
  Converter? Function(CommandsPlugin plugin)? converter;
  Check? Function(CommandsPlugin plugin)? check;
  ChatCommand? command;

  late String name;
  late final List<String>? aliases;
  late final String category;
  late final String description;
  late final Function execute;
  late BotCommandPermissions permissionsRequired;
  late final bool enforcePermissions;
  late final bool noGroup;
  late String group;
  String? extendedDescription;

  BotCommand(this.name, this.category, this.description, this.execute, {this.permissionsRequired = BotCommandPermissions.any, this.extendedDescription, this.enforcePermissions = true, this.noGroup = false, this.aliases, CommandOptions? options, this.group = ""}) {
    final wrappedExecute = (MessageChatContext context, List<dynamic> args) async {
      await Function.apply(execute, [context, ...args]);
    };

    if (group.trim().isEmpty) group = category.toLowerCase();
    if (dev) group = "dev_$group";

    commandRegistry[name] = this;
    if (dev && noGroup) name = "dev_$name";
    command = ChatCommand(name, description, id(name, execute), options: options ?? CommandOptions(), aliases: aliases ?? []);
  }

  @Deprecated("Use BotConverter instead.")
  BotCommand.converter(this.converter);
  BotCommand.check(this.check);

  @Deprecated("Use the unnamed constructor instead.")
  factory BotCommand.command(String name, String description, Function execute, CommandAttributes attributes, {CommandOptions? options, String group = "", bool noGroup = false}) {
    return BotCommand(name, attributes.category, description, execute, extendedDescription: attributes.extendedDescription, permissionsRequired: attributes.permissionsRequired, enforcePermissions: false, group: group, noGroup: noGroup);
  }

  ChatCommand getCommandUnsafe(CommandsPlugin plugin) {
    return command!;
  }

  static Map<String, BotCommand> commandRegistry = {};
  static bool useGroups = true;

  static void disableGroups() {
    useGroups = false;
  }

  static List<CommandRegisterable<CommandContext>> getFromRegistry(CommandsPlugin plugin) {
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

class BotConverter {
  final String id;
  final Converter? Function(CommandsPlugin plugin) callback;

  const BotConverter(this.id, this.callback);

  BotCommand toBotCommand() {
    return BotCommand.converter(callback);
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

BotCommand defaultCheck(KVStore store) => BotCommand.check((plugin) {
  return Check((context) async {
    if (isIgnored(store, context.user.id)) return false;
    final command = BotCommand.getCommand(context.command.name.replaceFirst("dev_", ""));

    if (command == null) {
      Logger.error("Check", "Invalid command: ${context.command.name}");
      return false;
    }

    if (command.enforcePermissions) {
      if (command.permissionsRequired == BotCommandPermissions.owner) {
        if (await context.assureOwner() == false) return false;
      } else if (command.permissionsRequired == BotCommandPermissions.admin || command.permissionsRequired == BotCommandPermissions.claimer) {
        if (context.guild == null) {
          context.respondWithError("No guild found.");
          return false;
        }

        final settings = ServerSettings(store, context.guild!.id);
        if (await context.assurePerms(command.permissionsRequired, settings) == false) return false;
      }
    }

    return true;
  });
});

bool isIgnored(KVStore store, Snowflake id) {
  return (BotSettings(store).ignored.get() ?? []).any((x) => x == id);
}