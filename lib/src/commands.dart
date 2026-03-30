import 'package:calebh101_discord/calebh101_discord.dart';

class BotCommand {
  Converter? Function(CommandsPlugin plugin)? converter;
  Check? Function(CommandsPlugin plugin)? check;
  Command? command;

  late final String name;
  late final String category;
  late final String description;
  late final Function execute;
  late BotCommandPermissions permissionsRequired;
  String? extendedDescription;
  CommandOptions? options;

  BotCommand(this.name, this.category, this.description, this.execute, {this.permissionsRequired = BotCommandPermissions.any, this.extendedDescription}) {
    commands[name] = this;
    command = ChatCommand(name, description, id(name, execute), options: options ?? CommandOptions());
  }

  BotCommand.converter(this.converter);
  BotCommand.check(this.check);

  @Deprecated("Use the unnamed constructor instead.")
  BotCommand.command(this.name, this.description, this.execute, CommandAttributes attributes, {this.options}) : converter = null {
    commands[name] = BotCommand(name, attributes.category, description, execute, permissionsRequired: attributes.permissionsRequired, extendedDescription: attributes.extendedDescription);
    command = ChatCommand(name, description, id(name, execute), options: options ?? CommandOptions());
  }

  static Map<String, BotCommand> commands = {};

  static Map<String, int> getAllCategories() {
    Map<String, int> results = {};

    for (final x in commands.entries) {
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

BotCommand defaultCheck(KVStore store) => BotCommand.check((plugin) {
  return Check((context) async {
    if (isIgnored(store, context.user.id)) return false;
    final command = BotCommand.commands[context.command.name];

    if (command == null) {
      Logger.error("Check", "Invalid command: ${context.command.name}");
      return false;
    }

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

    return true;
  });
});

bool isIgnored(KVStore store, Snowflake id) {
  return (BotSettings(store).ignored.get() ?? []).any((x) => x == id);
}