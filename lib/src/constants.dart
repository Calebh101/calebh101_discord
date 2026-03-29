import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:system_info/system_info.dart';

const defaultPrefix = "!";
const enableKill = true;

typedef DefinedUser = ({String name, String username, Snowflake id});
typedef DefinedServer = ({Snowflake id, Uri? invite});

const DefinedUser calebh101 = (
  name: "Caleb",
  username: "calebh101",
  id: Snowflake(1225628518021599264),
);

final DefinedServer calebh101Server = (
  id: Snowflake(1300649617381396480),
  invite: Uri.parse("https://discord.gg/gbZyPuqZ6n"),
);

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  if (event.guild == null) return defaultPrefix;
  final settings = getSettings.call(event.guild!);
  if (settings == null) return defaultPrefix;

  final prefix = settings.prefix.get() ?? defaultPrefix;
  return prefix;
};

BotCommand sendMessageAs() => BotCommand.command("sendmessage", "Send a message on my behalf.", (ChatContext context, String content, [GuildTextChannel? channel, Message? reply]) async {
  if (await context.assureOwner() == false) return;
  final c = channel ?? context.channel;
  if (c is! GuildTextChannel) return context.respondWithError("The selected channel is not a valid channel.\nExpected: `GuildTextChannel`, got: `${c.runtimeType}`");
  if (context.guild == null) return context.respondWithError("No guild found.");

  try {
    await c.sendMessage(MessageBuilder(content: content, referencedMessage: reply != null ? MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: reply.id) : null));
    await context.respond(MessageBuilder(content: "Message sent to ${c.toMention()}.\n-# Reply ID: ${reply?.id ?? null.toDiscordCodeString()}"), level: ResponseLevel.hint);
  } catch (e) {
    Logger.warn("SendMessageAs", "Unable to send message from ${channel?.id}: $e");
    context.respondWithError("Unable to send message.", level: ResponseLevel.private);
  }
}, CommandAttributes(category: "Bot"));

BotCommand deleteMyMessageCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command(
  "deletemessage", "Delete my message.",
  (ChatContext context, Snowflake id, [GuildTextChannel? targetChannel]) async {
    final owner = isOwner(id: context.user.id);

    if (context.guild != null && !owner) {
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("No settings found.");
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    } else {
      if (!owner) return context.respondWithError("You are not the owner of me.");
    }

    final channel = targetChannel ?? context.channel;

    try {
      final message = await channel.messages.get(id);
      if (message.author.id != context.client.user.id) return context.respondWithError("This message is not mine.", level: ResponseLevel.hint);
      await message.delete();
      await context.respond(MessageBuilder(content: "Message `${message.id}` deleted."), level: ResponseLevel.hint);
    } catch (e) {
      Logger.warn("DeleteMyMessage", "Unable to delete message $id from channel ${channel.id}: $e");
      context.respondWithError("Unable to delete message.", level: ResponseLevel.private);
    }
  },
  CommandAttributes(category: "Bot"),
);

BotCommand editMyMessageCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command(
  "editmessage", "Edit a message of mine.",
  (ChatContext context, Snowflake id, String content, [GuildTextChannel? targetChannel]) async {
    final owner = isOwner(id: context.user.id);

    if (context.guild != null && !owner) {
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("No settings found.");
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    } else {
      if (!owner) return context.respondWithError("You are not the owner of me.");
    }

    final channel = targetChannel ?? context.channel;

    try {
      final message = await channel.messages.get(id);
      if (message.author.id != context.client.user.id) return context.respondWithError("This message is not mine.", level: ResponseLevel.hint);
      await message.edit(MessageUpdateBuilder(content: content));
      await context.respond(MessageBuilder(content: "Message `${message.id}` edited."), level: ResponseLevel.hint);
    } catch (e) {
      Logger.warn("EditMyMessage", "Unable to edit message $id from channel ${channel.id}: $e");
      context.respondWithError("Unable to edit message.", level: ResponseLevel.private);
    }
  },
  CommandAttributes(category: "Bot"),
);

BotCommand restartCommand() => BotCommand.command("restart", "Restart the bot.", (ChatContext context) async {
  if (await context.assureOwner() == false) return;
  await context.respond(MessageBuilder(content: "Restarting..."));
  Logger.print("Commands.Kill", "User ${context.user.id} requested my restart.");
  await close.call(ExitCode.restart);
}, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.owner));

BotCommand messageMe() => BotCommand.command("messageme", "DM me.", (ChatContext context) async {
  bool dmSuccessful = false;

  try {
    (await context.client.users.createDm(context.user.id)).sendMessage(MessageBuilder(
      content: "Hey there, <@${context.user.id}>!",
    ));

    dmSuccessful = true;
  } catch (e) {
    Logger.warn("Commands.Suggestion.Deny", "Unable to open DM: $e");
  }

  await context.respond(MessageBuilder(content: dmSuccessful ? "<@${context.user.id}>, I have DMed you." : "<@${context.user.id}>, I was **not** able to DM you."), level: ResponseLevel.hint);
}, CommandAttributes(category: "Bot"));

BotCommand aboutCommand(KVStore? store) => BotCommand.command("about", "See stats about this bot.", (ChatContext context) async {
  final settings = store != null && context.guild != null ? ServerSettings(store, context.guild!.id) : null;
  final prefix = settings?.prefix.get() ?? "!";

  await context.respond(MessageBuilder(
    content: [
      "**$globalBotName**: A bot that does something",
      "Version $botVersion by [Calebh101](<https://github.com/Calebh101>)",
      null,
      "Current prefix: `$prefix`",
      "To see all commands, run `${prefix}help`.",
      null,
      [
        "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion}".trim(),
        (() {
          final processor = SysInfo.processors.first;
          return "${processor.vendor} ${processor.name}".trim();
        }()),
      ].join("\n").trim().toDiscordCodeBlock(),
      null,
      "Built with [nyxx](<https://pub.dev/packages/nyxx>), running on Dart:",
      Platform.version.trim().toDiscordCodeBlock(),
      if (globalSupportServer != null) ...["For support: ${globalSupportServer!.invite}"],
    ].map((x) => x ?? "").join("\n"),
  ));
}, CommandAttributes(category: "Bot"));

BotCommand pingCommand() => BotCommand.command(
  "ping", "Pong!",
  (ChatContext context) async {
    final latency = context.client.httpHandler.latency;
    final realLatency = context.client.httpHandler.realLatency;
    final gatewayLatency = context.client.gateway.latency;

    final Map<String, String> keys = {
      "HTTP latency": formatLatency(latency),
      "Real latency": formatLatency(realLatency),
      if (gatewayLatency.inMicroseconds > 0) "Gateway latency": formatLatency(gatewayLatency),
    };

    await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\n\n${keys.entries.map((x) {
      return "> ${x.key}: **${x.value}**";
    }).join("\n")}"));
  },
  CommandAttributes(category: "Bot"),
);

BotCommand killCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("kill", "Kill the bot. He will be sad.", (ChatContext context) async {
  if (!isOwner(id: context.user.id)) {
    context.respondWithError("You are not the owner of me!");
    return;
  }

  await context.respond(MessageBuilder(content: "I am now dead."));
  Logger.print("Commands.Kill", "User ${context.user.id} requested my death.");
  close.call();
}, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Bot"));

List<BotCommand> prefixCommands(ServerSettings? Function(Guild guild) getSettings) => [
    BotCommand.command("prefix", "Get/set the bot's prefix.", (ChatContext context, [String? prefix]) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("Unable to load settings.");

      if (prefix == null) {
        await context.respond(MessageBuilder(
          content: "Prefix is currently set to `${settings.prefix.get() ?? defaultPrefix}`.",
        ));

        return;
      }

      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      final old = settings.prefix.get();
      settings.prefix.set(prefix);

      Modlog.add(ModlogEvent(
        "prefix.change",
        guild: context.guild,
        title: "Prefix Changed",
        fields: {
          "Was": old.toDiscordCodeBlock(),
          "Now": prefix.toDiscordCodeBlock(),
          "Default": defaultPrefix.toDiscordCodeBlock(),
        },
        settings: settings,
      ));

      await context.respond(MessageBuilder(
        content: "Prefix set to `$prefix`!",
      ));
    }, CommandAttributes(category: "Bot")),
  BotCommand.command("resetprefix", "Reset the bot's prefix for this server.", (ChatContext context) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final old = settings.prefix.get();
    settings.prefix.delete();

    Modlog.add(ModlogEvent(
      "prefix.change",
      guild: context.guild,
      title: "Prefix Reset",
      fields: {
        "Was": old.toDiscordCodeBlock(),
        "Now": null.toDiscordCodeBlock(),
        "Default": defaultPrefix.toDiscordCodeBlock(),
      },
      settings: settings,
    ));

    context.respond(MessageBuilder(
      content: "Prefix set to `$defaultPrefix`!",
    ));
  }, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.admin))
];

BotCommand helpCommand(ServerSettings? Function(Guild guild) getSettings, CommandsPlugin plugin, {bool useCategories = true}) => BotCommand.command("help", "Show help for all commands, or a specific command${useCategories ? "/category" : ""}.", (ChatContext context, [@Description("Command or category to search.") String? command]) async {
  final settings = context.guild != null ? getSettings.call(context.guild!) : null;
  final commands = plugin.walkCommands().toList()..sort((a, b) => a.name.compareTo(b.name));
  final categories = BotCommand.getAllCategories();

  String getDescription(Command command) {
    if (command is ChatCommand) return command.description;
    return "Does something.";
  }

  CommandAttributes? getAttributes(Command command) {
    return BotCommand.commandAttributesMap[command.name];
  }

  String? getPerms(Command command) {
    final attributes = getAttributes(command);
    return attributes?.permissionsRequired == BotCommandPermissions.any ? null : attributes?.permissionsRequired.name;
  }

  if (command == null) {
    await respondWithPagination(
      context,
      PaginatedEmbedBuilder(
        title: "All Commands for $globalBotName",
        description: "Current prefix: `${settings?.prefix.get() ?? "!"}`",
        footer: ElementBasedEmbedFooterBuilder(elements: ["${commands.length} commands", if (categories.isNotEmpty) "${categories.length} categories"]),
        color: await getPrimaryColor(context.member) ?? primaryBotColor,
        pages: EmbedPage.generate(List.generate(commands.length, (i) {
          final command = commands.elementAt(i);
          final attributes = getAttributes(command);
          return EmbedFieldBuilder(name: [command.name, if (attributes != null) attributes.category].join(" - "), value: [getDescription(command), if (getPerms(command) != null) "Requires perms: `${getPerms(command)}`"].join(" "), isInline: false);
        })),
      ),
      settings: settings,
    );
  } else {
    final category = useCategories ? categories.entries.firstWhereOrNull((x) => x.key == command.trim()) : null;

    if (category != null) {
      if (category.value <= 0) return context.respondWithError("Category ${category.key} has no commands.");
      final commandsInCategory = commands.where((x) => getAttributes(x)?.category == category.key);

      await respondWithPagination(
        context,
        PaginatedEmbedBuilder(
          title: "All Commands for Category ${category.key}",
          footer: ElementBasedEmbedFooterBuilder(elements: ["${commandsInCategory.length} commands"]),
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          pages: EmbedPage.generate(List.generate(commandsInCategory.length, (i) {
            final command = commandsInCategory.elementAt(i);

            return EmbedFieldBuilder(name: command.name, value: [
              getDescription(command),
              if (getPerms(command) != null) "Requires perms: `${getPerms(command)}`",
            ].join(" "), isInline: false);
          })),
        ),
        settings: settings,
      );
    } else {
      final c = plugin.getCommand(StringView(command));
      if (c == null) return context.respondWithError("Invalid command${useCategories ? "/category" : ""}: `$command`");
      final attributes = getAttributes(c);

      await context.respond(MessageBuilder(embeds: [
        EmbedBuilder(
          title: "Command `${c.name}`",
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          description: [
            if (attributes != null) "Category: ${attributes.category}",
            getDescription(c),
            if (getPerms(c) != null) "Requires perms: `${getPerms(c)}`",
            if (attributes?.extendedDescription != null) "\n${attributes?.extendedDescription}",
          ].join("\n"),
        ),
      ]));
    }
  }
}, CommandAttributes(category: "Bot"));

BotCommand echoDebugCommand(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("echo", "Echo the input text from the bot.", (ChatContext context, String text, [int count = 1]) async {
  if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
  final settings = getSettings.call(context.guild!);
  if (settings == null) return context.respondWithError("Unable to load settings.");
  if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

  await context.respond(MessageBuilder(
    content: text * count,
  ));
}, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug"));

BotCommand listAllServerSettings(ServerSettings? Function(Guild guild) getSettings) => BotCommand.command("allsettings", "List all settings for this server. Admin only.", (ChatContext context) async {
  if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
  final settings = getSettings.call(context.guild!);
  if (settings == null) return context.respondWithError("Unable to load settings.");
  if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
  final all = settings.getAll().entries;

  context.respond(MessageBuilder(
    content: "All settings for *${context.guild?.name}*:\n${all.map((x) => "- `${x.key}`: `${x.value}`").join("\n")}",
  ), level: ResponseLevel.private);
}, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server"));

List<BotCommand> adminRoles(ServerSettings? Function(Guild guild) getSettings) => [
  BotCommand.command("addadminuser", "Add an admin user.", (ChatContext context, User user) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    final admins = settings.admins.get() ?? [];

    if (admins.any((x) => x["type"] == "user" && x["id"] == user.id.toString())) {
      return context.respond(MessageBuilder(
        content: "${await userToString(user)} is already an admin.",
      )).toVoid();
    }

    admins.add({"type": "user", "id": user.id.toString()});
    settings.admins.set(admins);

    Modlog.add(ModlogEvent(
      "adminuser.add",
      guild: context.guild,
      title: "Admin User Added",
      fields: {
        "Who": "<@${user.id}>",
        "Author": "<@${context.user.id}>",
      },
      settings: settings,
    ));

    context.respond(MessageBuilder(
      content: "Added ${await userToString(user)} as an admin!",
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server")),
  BotCommand.command("addadminrole", "Add a role as admin.", (ChatContext context, Role role) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    final admins = settings.admins.get() ?? [];

    if (admins.any((x) => x["type"] == "role" && x["id"] == role.id.toString())) {
      return context.respond(MessageBuilder(
        content: "Role *${role.name}* is already an admin.",
      )).toVoid();
    }

    admins.add({"type": "role", "id": role.id.toString()});
    settings.admins.set(admins);

    Modlog.add(ModlogEvent(
      "adminrole.add",
      guild: context.guild,
      title: "Admin Role Added",
      fields: {
        "Who": "<@${role.id}>",
        "Author": "<@${context.user.id}>",
      },
      settings: settings,
    ));

    context.respond(MessageBuilder(
      content: "Added role *${role.name}* as admin!",
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server")),
  BotCommand.command("removeadminuser", "Remove a user from admin.", (ChatContext context, User user) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final admins = settings.admins.get() ?? [];
    bool found = false;

    admins.removeWhere((x) {
      final y = x["type"] == "user" && x["id"] == user.id.toString();
      if (y) found = true;
      return y;
    });

    if (found) {
      settings.admins.set(admins);

      Modlog.add(ModlogEvent(
        "adminuser.remove",
        guild: context.guild,
        title: "Admin User Removed",
        fields: {
          "Who": "<@${user.id}>",
          "Author": "<@${context.user.id}>",
        },
        settings: settings,
      ));
    }

    context.respond(MessageBuilder(
      content: found ? "Removed ${await userToString(user)} from admin." : "${await userToString(user)} is not currently an admin.",
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server")),
  BotCommand.command("removeadminrole", "Remove a role from admin.", (ChatContext context, Role role) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final admins = settings.admins.get() ?? [];
    bool found = false;

    admins.removeWhere((x) {
      final y = x["type"] == "role" && x["id"] == role.id.toString();
      if (y) found = true;
      return y;
    });

    if (found) {
      settings.admins.set(admins);

      Modlog.add(ModlogEvent(
        "adminrole.remove",
        guild: context.guild,
        title: "Admin Role Removed",
        fields: {
          "Who": "<@${role.id}>",
          "Author": "<@${context.user.id}>",
        },
        settings: settings,
      ));
    }

    context.respond(MessageBuilder(
      content: found ? "Removed role *${role.name}* from admin." : "Role *${role.name}* is not currently admin.",
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Server")),
  BotCommand.command("claim", "Claim yourself as king of the bot!", (ChatContext context) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (context.member == null) return context.respondWithError("No member found.");
    final mainAdmin = settings.mainAdmin.get();

    if (mainAdmin == null || isOwner(id: context.member!.id)) {
      settings.mainAdmin.set(context.member!.id.toString());

      Modlog.add(ModlogEvent(
        "claim",
        guild: context.guild,
        title: "I Have Been Claimed",
        fields: {
          "Who": "<@${context.user.id}>",
          "Was": mainAdmin != null ? "<@$mainAdmin>" : null.toDiscordCodeBlock(),
        },
        settings: settings,
      ));

      context.respond(MessageBuilder(
        content: "<@${context.member!.id}> has claimed me!",
      ));

      if (mainAdmin != null) {
        final m = await () async {
          try {
            return (await context.client.users.createDm(Snowflake(int.parse(mainAdmin)))).sendMessage(MessageBuilder(content: "I have been unclaimed."));
          } catch (e) {
            Logger.warn("Commands.Claim", "Unable to open DM: $e");
          }
        }();

        try {
          if (m == null) return;
          final member = (await context.guild!.members.get(Snowflake(int.parse(mainAdmin))));
          await m.edit(MessageUpdateBuilder(content: "I have been reclaimed by ${await memberToString(context.member)}.\n-# I was claimed by ${await memberToString(member)}."));
        } catch (e) {
          Logger.warn("Commands.Claim", "User $mainAdmin not found: $e");
        }
      }
    } else {
      final m = await context.respond(MessageBuilder(
        content: "I've already been claimed by someone else.",
      ));

      try {
        final member = (await context.guild!.members.get(Snowflake(int.parse(mainAdmin))));
        m.edit(MessageUpdateBuilder(content: "I've already been claimed by ${await memberToString(member)}."));
      } catch (e) {
        Logger.warn("Commands.Claim", "User $mainAdmin not found: $e");
      }
    }
  }, CommandAttributes(category: "Bot")),
  BotCommand.command("unclaim", "Step down as king of the bot. This will not be made known to others.", (ChatContext context) async {
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("Unable to load settings.");
    if (context.member == null) return context.respondWithError("No member found.");
    final old = settings.mainAdmin.get();

    if (old == null) {
      await context.respond(MessageBuilder(
        content: "I am unclaimed already.",
      ));
    } else if (old != context.member!.id.toString() && !isOwner(id: context.member!.id)) {
      await context.respond(MessageBuilder(
        content: "You are not the one who claimed me!",
      ));
    } else {
      settings.mainAdmin.delete();
      //if (context is MessageChatContext) await context.message.delete();

      Modlog.add(ModlogEvent(
        "claim",
        guild: context.guild,
        title: "I Have Been Unclaimed",
        fields: {
          "Who": "<@${context.user.id}>",
          "Was": "<@$old>",
        },
        settings: settings,
      ));

      await context.respond(MessageBuilder(
        content: "I have been unclaimed.",
      ), level: ResponseLevel.hint);

      final m = await () async {
        try {
          return (await context.client.users.createDm(Snowflake(int.parse(old)))).sendMessage(MessageBuilder(content: "I have been unclaimed."));
        } catch (e) {
          Logger.warn("Commands.Unclaim", "Unable to open DM: $e");
        }
      }();

      try {
        if (m == null) return;
        final member = (await context.guild!.members.get(Snowflake(int.parse(old))));
        await m.edit(MessageUpdateBuilder(content: "I have been unclaimed.\n-# I was claimed by ${await memberToString(member)}."));
      } catch (e) {
        Logger.warn("Commands.Unclaim", "User $old not found: $e");
      }
    }
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.claimer, category: "Bot")),
  BotCommand.command("owner", "See stats about who owns the bot, who owns the server, and who's claimed the bot.", (ChatContext context) async {
    final settings = getSettings.call(context.guild!);
    final mainAdmin = settings?.mainAdmin.get();
    Map<String, String> results = {};

    if (globalOwner != null) {
      results["Bot Owner"] = "**${globalOwner!.name}** (*${globalOwner!.username}*)";
    }

    if (mainAdmin != null) {
      try {
        final member = await context.guild!.members.get(Snowflake(int.parse(mainAdmin)));
        results["Bot Claimer"] = (await memberToString(member))!;
      } catch (e) {
        Logger.warn("Commands.Owner", "Unable to get claimer $mainAdmin: $e");
        results["Bot Claimer"] = "User `$mainAdmin`";
      }
    } else {
      results["Bot Claimer"] = "Not claimed yet!";
    }

    if (context.guild != null) {
      try {
        final serverOwner = await context.guild!.members.get(context.guild!.ownerId);
        results["Server Owner"] = (await memberToString(serverOwner))!;
      } catch (e) {
        Logger.warn("Commands.Owner", "Unable to get server owner: $e");
      }
    }

    await context.respond(MessageBuilder(embeds: [
      EmbedBuilder(
        fields: List.generate(results.length, (i) {
          final entry = results.entries.elementAt(i);
          return EmbedFieldBuilder(name: entry.key, value: entry.value, isInline: false);
        }),
      ),
    ]));
  }, CommandAttributes(category: "Bot")),
  BotCommand.command("status", "See your status.", (ChatContext context, [@Description('The member to check') Member? member]) async {
    final m = member ?? context.member;
    final u = m?.user ?? context.user;
    List<String> attributes = ["Alive"];

    if (context.guild != null && context.member != null) {
      attributes.add("In *${context.guild!.name}*");
      final settings = getSettings.call(context.guild!);

      if (settings != null) {
        final mainAdmin = settings.mainAdmin.get();
        final admins = settings.admins.get();

        if (m != null) {
          for (final a in admins ?? []) {
            if (a["type"] == "user") {
              if (a["id"] == m.id.toString()) {
                attributes.add("Admin user");
              }
            } else if (a["type"] == "role") {
              for (final x in m.roles) {
                if (a["id"] == x.id.toString()) {
                  attributes.add("Admin (role: ${(await x.get()).name})");
                }
              }
            }
          }
        }

        if (mainAdmin == u.id.toString()) {
          attributes.add("Claimer");
        }
      }
    }

    if (globalOwner != null && globalOwner!.id == u.id) {
      attributes.add("Owner");
    }

    try {
      await context.respond(MessageBuilder(
        content: "### Attributes for ${await userOrMemberToString(m, u)}${context.guild != null ? " in *${context.guild!.name}*" : ""}\n\n${attributes.map((x) => "- $x").join("\n")}",
      ));
    } catch (e) {
      Logger.warn("Commands.Status", e);
    }
  }, CommandAttributes(category: "User")),
  BotCommand.command("ignoreowner", "Ignore the bot owner's status temporarily.", (ChatContext context) async {
    if (!isOwner(id: context.user.id, overrideIgnoreOwner: true)) return context.respondWithError("You are not the owner of me.");
    ignoreOwner = !ignoreOwner;
    await context.respond(MessageBuilder(content: "Owner is now **${ignoreOwner ? "temporarily ignored": "unignored"}**."));
  }, CommandAttributes(category: "Debug", permissionsRequired: BotCommandPermissions.owner)),
];

final Map<String? Function(MessageCreateEvent event), num> pingPhrases = {
  (_) => "WHAT'S ALL THAT NOISE??": 50,
  (_) => "Ow!": 100,
  (_) => "Pong!": 100,
  (_) => "Hey there!": 100,
  (e) => "Hi there, <@${e.member!.id}>!": 100,
  (_) => "AGHGHGHGHGHGHGHGHGHGHGHGHGHGHGHHGHG": 5,
};