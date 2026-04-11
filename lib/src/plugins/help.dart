import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class HelpPlugin extends BotPlugin {
  HelpPlugin() : super(id: "help", name: "Help Commands", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      helpCommand(store),
      BotCommand("plugins", "Help", "List all plugins.", (ChatContext context) async {
        final plugins = pluginStore.plugins;

        await respondWithPagination(
          context, PaginatedEmbedBuilder(
            pages: EmbedPage.generateFromItems(plugins.map((x) => "- **${x.name}**: `${x.id}` ${x.version}").toList()),
            title: "All Plugins",
            footer: ElementBasedEmbedFooterBuilder(elements: ["${plugins.length} Plugins"]),
            color: await getPrimaryColor(context.member) ?? primaryBotColor,
          ),
          settings: context.guild != null ? ServerSettings(store, context.guild!.id) : null,
        );
      }),
    ];
  }

  BotCommand helpCommand(KVStore store, {bool useCategories = true}) => BotCommand.command("help", "Show help for all commands, or a specific command${useCategories ? "/category" : ""}.", (ChatContext context, [@Description("Command or category to search.") String? command, bool dump = false]) async {
    Logger.print("Help", "Loading help with input $command (dump=$dump)");
    if (command?.trim() == "all") command = null;
    final settings = context.guild != null ? ServerSettings(store, context.guild!.id) : null;
    final commands = BotCommand.commands.entries.toList()..sort((a, b) => a.value.name.compareTo(b.value.name));
    final categories = BotCommand.getAllCategories();
    PaginatedEmbedBuilder? embed;

    String getDescription(BotCommand command) {
      return command.description;
    }

    String? getPerms(BotCommand command) {
      return command.permissionsRequired == BotCommandPermissions.any ? null : command.permissionsRequired.name;
    }

    if (command == null) {
      embed = PaginatedEmbedBuilder(
        title: "All Commands for $globalBotName",
        description: dump ? null : "Current prefix: `${settings?.prefix.get() ?? defaultPrefix}`",
        footer: ElementBasedEmbedFooterBuilder(elements: ["${commands.length} commands", if (categories.isNotEmpty) "${categories.length} categories"]),
        color: await getPrimaryColor(context.member) ?? primaryBotColor,
        pages: EmbedPage.generate(List.generate(commands.length, (i) {
          final command = commands.elementAt(i).value;
          return EmbedFieldBuilder(name: [command.name, command.category].join(" - "), value: [getDescription(command), if (getPerms(command) != null) "Requires perms: `${getPerms(command)}`"].join(" "), isInline: false);
        })),
      );
    } else if (command.trim() == "categories") {
      embed = PaginatedEmbedBuilder(
        title: "All Categories",
        footer: ElementBasedEmbedFooterBuilder(elements: ["${categories.length} categories"]),
        color: await getPrimaryColor(context.member) ?? primaryBotColor,
        pages: EmbedPage.generate(List.generate(categories.length, (i) {
          final command = categories.entries.elementAt(i);

          return EmbedFieldBuilder(name: command.key, value: [
            "${command.value} commands",
          ].join("\n"), isInline: false);
        })),
      );
    } else {
      final category = useCategories ? categories.entries.firstWhereOrNull((x) => x.key == command!.trim()) : null;

      if (category != null) {
        if (category.value <= 0) return context.respondWithError("Category ${category.key} has no commands.");
        final commandsInCategory = commands.where((x) => x.value.category == category.key);

        embed = PaginatedEmbedBuilder(
          title: "All Commands for Category ${category.key}",
          footer: ElementBasedEmbedFooterBuilder(elements: ["${commandsInCategory.length} commands"]),
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          pages: EmbedPage.generate(List.generate(commandsInCategory.length, (i) {
            final command = commandsInCategory.elementAt(i).value;

            return EmbedFieldBuilder(name: command.name, value: [
              getDescription(command),
              if (getPerms(command) != null) "Requires perms: `${getPerms(command)}`",
            ].join(" "), isInline: false);
          })),
        );
      } else {
        final c = commands.firstWhereOrNull((x) => x.key == command)?.value;
        if (c == null) return context.respondWithError("Invalid command${useCategories ? "/category" : ""}: `$command`");

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "Command `${c.name}`",
            color: await getPrimaryColor(context.member) ?? primaryBotColor,
            description: [
              "Category: ${c.category}",
              getDescription(c),
              if (getPerms(c) != null) "Requires perms: `${getPerms(c)}`",
              if (c.extendedDescription != null) "\n${c.extendedDescription}",
            ].join("\n"),
          ),
        ]));
      }
    }

    if (embed != null) {
      Logger.print("Help", "Received embed of ${embed.pages.length} pages");

      if (dump) {
        await context.respond(MessageBuilder(content: "Embed dumped. Pages: ${embed.pages.length}"), level: ResponseLevel.hint);
        await dumpPagination(embed, context.channel);
      } else {
        await respondWithPagination(context, embed, settings: settings);
      }
    } else {
      Logger.print("Help", "No embed received");
    }
  }, CommandAttributes(category: "Help", extendedDescription: "Other options:\n- `help all`: Same as just `help`\n- `help categories`: Display all categories"));
}