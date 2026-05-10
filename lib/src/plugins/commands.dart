import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:nyxx_commands/src/mirror_utils/function_data.dart';
import 'package:collection/collection.dart';

Map<Snowflake, int> rTrain = {};

class HelpPlugin extends BotPluginLegacy {
  HelpPlugin() : super(id: "help", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      helpCommand<T>(store, plugin),
      BotCommand("plugins", "Commands", "List all plugins.", (T context) async {
        final plugins = pluginStore.plugins;

        await respondWithPagination(
          context, PaginatedEmbedBuilder(
            pages: EmbedPage.generateFromItems(plugins.map((x) => "- `${x.id}` ${x.version}").toList()),
            title: "All Plugins",
            footer: ElementBasedEmbedFooterBuilder(elements: ["${plugins.length} Plugins"]),
            color: await getPrimaryColor(context.member) ?? primaryBotColor,
          ),
          settings: context.guild != null ? ServerSettings(store, context.guild!.id) : null,
        );
      }),
      BotCommand("plugin", "Commands", "Find a plugin by its ID.", (T context, String id) async {
        final plugin = pluginStore.plugins.firstWhereOrNull((x) => x.id == id.trim());
        if (plugin == null) return context.respondWithError("Invalid plugin ID: `$id`\nRun `plugins` to view all plugins.");

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "Plugin Found",
            description: "ID: `${plugin.id}`\nVersion: ${plugin.version}\nIdentifier: `${plugin.className}`\n\n${plugin.description}",
            color: await getColor(context.member),
          ),
        ]));
      }),
      BotCommand("categories", "Commands", "List all categories.", (T context) async {
        final categories = BotCommand.getAllCategories().entries.sorted((a, b) => a.key.compareTo(b.key));

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "All Categories",
          footer: ElementBasedEmbedFooterBuilder(elements: ["${categories.length} categories"]),
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          pages: EmbedPage.generate(List.generate(categories.length, (i) {
            final command = categories.elementAt(i);

            return EmbedFieldBuilder(name: command.key, value: [
              "${command.value} commands",
            ].join("\n"), isInline: false);
          })),
        ), settings: context.guild != null ? ServerSettings(store, context.guild!.id) : null);
      }),
      BotCommand("search", "Commands", "Search for a command.", (T context, GreedyString query) async {
        String aliases(BotCommand command) {
          return "(AKA ${command.aliases!.join(", ")})";
        }

        String getName(BotCommand command) {
          return [if (!command.noGroup && BotCommand.useGroups) command.group, command.name, if (command.aliases != null) aliases(command)].join(" ");
        }

        final commands = [...BotCommand.commandRegistry.entries, ...BotCommand.getAllCategories().entries];
        final List<({String name, String description, double score, int type})> ranking = commands.map((x) => (name: x.value is BotCommand ? getName(x.value as BotCommand) : x.key, description: x.value is BotCommand ? (x.value as BotCommand).description : "${x.value} commands", score: x.value is BotCommand ? (x.value as BotCommand).getNames().map((y) => fuzzyScore(query.data, y)).reduce((a, b) => a > b ? a : b) : fuzzyScore(query.data, x.key), type: x.value is int ? 1 : 0 /* command = 0, category = 1 */)).sorted((a, b) => b.score.compareTo(a.score));
        final results = ranking.sublist(0, min(6, ranking.length));
        if (results.isEmpty) return context.respondWithError("No results found.");

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "${results.length} Results",
            description: query.toDiscordCodeBlock(),
            color: await getColor(context.member),
            footer: EmbedFooterBuilder(text: "${ranking.length} Total"),
            fields: results.map((x) {
              return EmbedFieldBuilder(
                name: x.name,
                value: x.description,
                isInline: false,
              );
            }).toList(),
          ),
        ]));
      }),
      BotCommand("dumphelp", "Commands", "Dump all help as markdown.", (T context) {
        context.respondWithError("This command is not implemented yet.");
      }),
      BotCommand("r", "Commands", "Get your last message, and try to use it to run a command.", (MessageChatContext context) async {
        late List<Message> allMessages;

        try {
          allMessages = await context.channel.messages.fetchMany(limit: 20, before: context.message.id);
        } catch (e) {
          Logger.warn("Commands.r", "Unable to get messages: $e");
          return context.respondWithError("Unable to get messages.");
        }

        final message = allMessages.sorted((a, b) => b.timestamp.compareTo(a.timestamp)).firstWhereOrNull((x) => x.author.id == context.user.id);
        Logger.print("Commands.r", "Received message ${message?.id} from user ${context.user.id}:\n${message?.content.trim()}");
        if (message == null) return context.respondWithError("Couldn't find a recent message from you.");
        if (message.content.trim() == context.message.content.trim()) return context.respondWithError("You can't train repeats.");

        final event = MessageCreateEvent(gateway: context.client.gateway, guildId: context.guild?.id, member: context.member, mentions: [], message: message);
        final x = await plugin.eventManager.processMessageCreateEvent(event);

        if (x == null) {
          await context.respond(MessageBuilder(content: "Couldn't process your latest message: ${context.createDiscordLink(message.id)}"));
        }
      }, options: BotCommandOptions(type: CommandType.textOnly)),
      BotCommand("eval", "Bot", "Evaluate commands.", (MessageChatContext context, GreedyQuotedList input) async {
        int success = 0;

        for (String x in input.input) {
          if (x.startsWith(context.prefix)) x = x.replaceFirst(context.prefix, "");
          final items = x.split(" ");
          Logger.print("eval", "${context.user.id}: $x");

          final command = BotCommand.commandRegistry.entries.firstWhereOrNull((x) => x.key == items.first);
          if (command == null || command.value.command == null) continue;

          final m = await context.channel.sendMessage(MessageBuilder(content: "${context.prefix}$x"));
          await command.value.command!.invoke(MessageChatContext(message: m, prefix: context.prefix, rawArguments: items.length > 1 ? items.sublist(1).join(" ") : "", command: command.value.command!, user: context.user, member: context.member, guild: context.guild, channel: context.channel, commands: plugin, client: context.client));
          success++;
        }

        await context.respond(MessageBuilder(content: "Evaluated **$success** commands."));
      }, options: BotCommandOptions(type: CommandType.textOnly)),
      BotCommand("evalas", "Bot", "Evaluate commands as a user.", (MessageChatContext context, User user, GreedyQuotedList input) async {
        int success = 0;

        for (final x in input.input) {
          final items = x.split(" ");
          Logger.print("eval", "${context.user.id} (${user.id}): $x");
          final command = BotCommand.commandRegistry.entries.firstWhereOrNull((x) => x.key == items.first);
          if (command == null || command.value.command == null) continue;

          final m = await context.channel.sendMessage(MessageBuilder(content: "${context.prefix}$x", referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: context.message.id, failIfInexistent: false), allowedMentions: AllowedMentions(repliedUser: false)));

          try {
            await command.value.command!.invoke(MessageChatContext(message: m, prefix: context.prefix, rawArguments: items.length > 1 ? items.sublist(1).join(" ") : "", command: command.value.command!, user: user, member: await userToMember(user, guild: context.guild), guild: context.guild, channel: context.channel, commands: plugin, client: context.client));
          } on UncaughtException catch (e) {
            if (e.exception is CommandsException) onCommandError?.call(e.exception as CommandsException);
            else Logger.warn("evalas", "Error (${e.runtimeType}, ${e.exception.runtimeType}): ${e.exception}");
          } catch (e) {
            Logger.warn("evalas", "Error (${e.runtimeType}): $e");
            if (e is CommandsException) onCommandError?.call(e);
          }

          success++;
        }

        await context.respond(MessageBuilder(content: "Evaluated **$success** commands as user ${await memberFromUserToString(user, client: context.client, guild: context.guild)}."));
      }, options: BotCommandOptions(type: CommandType.textOnly)),
    ];
  }

  BotCommand helpCommand<T extends ChatContext>(KVStore store, CommandsPlugin plugin, {bool useCategories = true}) => BotCommand("help", "Commands", "Show help for all commands, or a specific command${useCategories ? "/category" : ""}.", (T context, [@Description("Command or category to search.") String? command, bool dump = false]) async {
    Logger.print("Help", "Loading help with input $command (dump=$dump)");
    if (command?.trim() == "all") command = null;
    final settings = context.guild != null ? ServerSettings(store, context.guild!.id) : null;
    final commands = BotCommand.commandRegistry.entries.toList()..sort((a, b) => a.value.name.compareTo(b.value.name));
    final categories = BotCommand.getAllCategories();
    PaginatedEmbedBuilder? embed;

    String getDescription(BotCommand command) {
      return command.description;
    }

    String? getPerms(BotCommand command) {
      return command.permissionsRequired == BotCommandPermissions.any ? null : command.permissionsRequired.name;
    }

    String aliases(BotCommand command) {
      return "(AKA ${command.aliases!.join(", ")})";
    }

    String getName(BotCommand command) {
      return [if (!command.noGroup && BotCommand.useGroups) command.group, command.name, if (command.aliases != null) aliases(command)].join(" ");
    }

    if (command == null) {
      embed = PaginatedEmbedBuilder(
        title: "All Commands for $globalBotName",
        description: dump ? null : "Current prefix: `${settings?.prefix.get() ?? defaultPrefix}`",
        footer: ElementBasedEmbedFooterBuilder(elements: ["${commands.length} commands", if (categories.isNotEmpty) "${categories.length} categories"]),
        color: await getPrimaryColor(context.member) ?? primaryBotColor,
        pages: EmbedPage.generate(List.generate(commands.length, (i) {
          final command = commands.elementAt(i).value;
          return EmbedFieldBuilder(name: [getName(command), command.category].join(" - "), value: [getDescription(command), if (getPerms(command) != null) "Requires perms: `${getPerms(command)}`"].join(" "), isInline: false);
        })),
      );
    } else {
      final c = commands.firstWhereOrNull((x) => [x.value.name, ...?x.value.aliases].contains(command?.split(" ").last))?.value;
      final category = useCategories ? categories.entries.firstWhereOrNull((x) => x.key.toLowerCase() == command?.toLowerCase().trim()) : null; // Fallback, so make it case-insensitive
      if (c == null && category == null) return context.respondWithError("Invalid command${useCategories ? "/category" : ""}: `$command`\nRun `search \"$command\"` to search through all commands.");

      if (c != null) {
        String argumentToString(ParameterData arg) {
          final converter = plugin.getConverter(arg.type);

          if (converter != null && converter.choices != null && converter.choices!.isNotEmpty) {
            final choices = converter.choices!.map((x) => x.name);
            return "${arg.name} [${choices.join(", ")}]";
          } else {
            return "${arg.name}${arg.isOptional ? "?" : ""} (${arg.type.internalType})";
          }
        }

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "Command ${getName(c)}",
            color: await getPrimaryColor(context.member) ?? primaryBotColor,
            description: [
              "${[if (!c.noGroup && BotCommand.useGroups) c.group, c.name].join(" ")} ${(c.command as ChatCommand).arguments.map((x) => argumentToString(x)).join(" ")}".toDiscordCodeBlock(),
              "Category: ${c.category}",
              if (getPerms(c) != null) "Requires perms: `${getPerms(c)}`",
              getDescription(c),
              if (c.extendedDescription != null) "\n${c.extendedDescription}",
            ].join("\n"),
          ),
        ]));
      } else if (category != null) {
        if (category.value <= 0) return context.respondWithError("Category ${category.key} has no commands.");
        final commandsInCategory = commands.where((x) => x.value.category == category.key);

        embed = PaginatedEmbedBuilder(
          title: "All Commands for Category ${category.key}",
          footer: ElementBasedEmbedFooterBuilder(elements: ["${commandsInCategory.length} commands"]),
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          pages: EmbedPage.generate(List.generate(commandsInCategory.length, (i) {
            final command = commandsInCategory.elementAt(i).value;

            return EmbedFieldBuilder(name: getName(command), value: [
              getDescription(command),
              if (getPerms(command) != null) "\nRequires perms: `${getPerms(command)}`",
            ].join(" "), isInline: false);
          })),
        );
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
  }, noGroup: true, aliases: ["commands"]);
}