import 'dart:async';
import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'xp.g.dart';

final double maxXpPerHour = 1000;
final double xpPerReaction = 1;
final double Function(int length) xpPerMessage = (length) => (double.parse(min(length / 1000, 0.2).toStringAsFixed(3))) * 1000; // Message length of 200+ => 200, 20 => 20, 2 => 20

class XPPlugin extends BotPluginLegacy {
  XPPlugin() : super(id: "xp", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyMemberList.converter(),
    ];
  }

  @override
  commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return xpCommands<T>(store);
  }

  List<BotCommand> xpCommands<T extends ChatContext>(KVStore store) => [
    BotCommand.command("leaderboard", "Get the current XP leaderboard.", (T context) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (settings.xpEnabled.get() != true) return context.respondWithError("XP is not enabled.");
      final banned = settings.xpBanned.get() ?? [];

      var values = store.getAllForKey<double>(Scope.userPerServer, "xp").entries
        .where((x) {
          final ids = UserPerServerSettings.parseId(x.key);
          if (ids.server != context.guild!.id) return false;
          if (banned.contains(ids.user)) return false;
          if (x.value <= 1) return false;
          return true;
        }).map((x) => MapEntry(UserPerServerSettings.parseId(x.key).user, x.value)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      Logger.print("Leaderboard", "Entries: ${values.length}");

      values = (await Future.wait(values.map((x) async {
        try {
          await context.guild!.members.get(x.key);
          return x;
        } catch (e) {
          Logger.warn("Leaderboard", "Unable to get user ${x.key}: $e");
        }
      }))).whereType<MapEntry<Snowflake, double>>().toList();

      Logger.print("Leaderboard", "Entries after: ${values.length}");
      const int maxLinesPerPage = 20;
      List<(int i, List<String>)> pages = [];
      List<String> currentPage = [];
      int currentPageLength = 0;

      for (int i = 0; i < values.length; i++) {
        final v = values[i];
        final Role? level = await getRole(context.guild!, Snowflake(levelFromXp(settings.xpLevels.get() ?? [], getRoundedXp(Calebh101BotUserPerServerSettings(store, context.guild!.id, v.key)))?.roleId ?? 0));

        currentPage.add([(v.key.value.toMention()), "**${roundXp(v.value)}** XP", if (level != null) level.toMention()].join(" "));
        currentPageLength++;

        if (currentPageLength >= maxLinesPerPage) {
          pages.add((pages.length, List.of(currentPage)));
          currentPage = [];
          currentPageLength = 0;
        }
      }

      if (currentPage.isNotEmpty) pages.add((pages.length, List.of(currentPage)));

      await respondWithPagination(
        context,
        PaginatedEmbedBuilder(
          title: "Leaderboard for ${context.guild!.name}",
          color: await getPrimaryColor(context.member) ?? primaryBotColor,
          timestamp: DateTime.now().toUtc(),
          pages: pages.map((x) {
            final i = x.$1;
            final value = x.$2;
            final length = value.length;

            return EmbedPage(fields: [
              EmbedFieldBuilder(name: "Members ${maxLinesPerPage * i + 1} - ${(maxLinesPerPage * i) + length}", value: value.join("\n"), isInline: false),
            ]);
          }).toList(),
        ),
        settings: settings,
      );
    }, CommandAttributes(category: "XP")),

    BotCommand.command("gamble", "Gamble your XP away.", (T context, double amountToBet) async {
      final member = context.member;
      final guild = context.guild;

      if (member == null || guild == null || member.user == null) return context.respondWithError("No guild/member found.");
      if (amountToBet % 10 != 0) return context.respondWithError("Bets must be in multiples of 10.");

      final serverSettings = Calebh101BotServerSettings(store, guild.id);
      final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
      final amount = amountToBet.toInt();
      final banned = serverSettings.xpBanned.get() ?? [];
      final current = settings.xp.get() ?? 0;

      if (banned.any((x) => x == member.id)) {
        return context.respondWithError("You are currently banned from the XP system.");
      }

      if (amount > current) {
        return context.respondWithError("You don't have enough XP! You only have **${roundXp(current)}**.");
      }

      late int chance;
      late num payout;

      if (amount < 100) {
        chance = 5;
        payout = amount / 10;
      } else if (amount < 500) {
        chance = 15;
        payout = amount / 5;
      } else {
        chance = 25;
        payout = amount / 2;
      }

      final value = Random.secure().nextInt(chance);
      final win = value == 0;
      Logger.print("Gamble", "Member ${member.id} bet $amount with chance $chance and payout $payout to get $value and ${win ? "win" : "lose"}");

      if (win) {
        await addXp(null, guild, member.user!, payout.toDouble(), client: context.client);
        await context.respond(MessageBuilder(content: "${await memberToString(member, client: context.client)} bet **$amount** and **won** ${roundXp(payout.toDouble())} XP! That puts them at **${roundXp(current + payout)}** XP."));
      } else {
        await addXp(null, guild, member.user!, -amount.toDouble(), client: context.client);
        await context.respond(MessageBuilder(content: "${await memberToString(member, client: context.client)} bet **$amount** and *lost*. That puts them at **${roundXp(current - amount)}** XP."));
      }
    }, CommandAttributes(category: "XP", extendedDescription: "- Each bet has to be a multiple of 10.\n- The more you bet, the less chance you have to win.")),

    BotCommand.command("xplevels", "List all set XP levels.", (T context) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      final roles = settings.xpLevels.get() ?? [];

      if (roles.isEmpty) {
        return context.respondWithError("No XP levels set.");
      }

      await context.respond(MessageBuilder(
        content: "## All XP Levels for *${context.guild!.name}*\n\n${(await Future.wait(roles.map((x) async {
          return "- ${await roleToString(await getRole(context.guild!, Snowflake(x.roleId)))}: **${x.requiredXp}** XP required";
        }))).join("\n")}",
      ));
    }, CommandAttributes(category: "XP")),

    BotCommand.command("addxplevel", "Add an XP level.", (T context, Role role, int requiredXp) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final roles = settings.xpLevels.get() ?? [];
      final level = XPLevel(requiredXp: requiredXp, roleId: role.id.value);
      roles.add(level);
      settings.xpLevels.set(roles);

      await context.respond(MessageBuilder(
        content: "Added XP level ${await roleToString(role)} with **$requiredXp** XP!",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("editxplevel", "Add an XP level's required XP.", (T context, Role role, int requiredXp) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final roles = settings.xpLevels.get() ?? [];
      final level = roles.firstWhereOrNull((x) => x.roleId == role.id.value);

      if (level == null) {
        return context.respondWithError("Invalid level: ${role.id}");
      }

      level.requiredXp = requiredXp;
      settings.xpLevels.set(roles);

      await context.respond(MessageBuilder(
        content: "Set XP level ${await roleToString(role)}'s required XP to **$requiredXp** XP.",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("removexplevel", "Remove an XP level by name.", (T context, Role role) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      var roles = settings.xpLevels.get() ?? [];
      roles = roles.where((x) => x.roleId != role.id.value).toList();
      settings.xpLevels.set(roles);

      await context.respond(MessageBuilder(
        content: "Removed XP level ${await roleToString(role)}.",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("setxpupdateschannel", "Set a channel for the bot to announce updates like level-ups.", (T context, [GuildTextChannel? channel]) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      settings.xpChannel.set(channel?.id.value);
      await context.respond(MessageBuilder(content: "XP updates channel ${channel != null ? "to ${channel.toMention()}" : "removed"}!"));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("xpupdateschannel", "Get the channel for the bot to announce updates like level-ups.", (T context) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);

      final id = settings.xpChannel.get();
      await context.respond(MessageBuilder(content: "XP updates channel ${id != null ? "is set to ${id.toChannel()}" : "not set"}."));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("reassignxp", "Reassign everyone's XP levels, or specific users'.", (T context, [GreedyMemberList? input]) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      String getMessage(int progress) {
        return "XP levels are being reassigned, please wait...\n-# Progress: $progress%";
      }

      final m = await context.respond(MessageBuilder(content: getMessage(0)));
      final members = input?.input ?? await getAllMembers(context.guild!);

      for (int i = 0; i < members.length; i++) {
        try {
          final member = members[i];
          final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, member.id);

          await evalXpRoles(guild: context.guild!, member: member, xp: userSettings.xp.get() ?? 0);
        } catch (e) {
          final member = members[i];
          Logger.warn("ReassignXP", "Error with user $i (${member.id}): $e");
        }
      }

      await context.updateMessage(m, MessageUpdateBuilder(content: "Process complete!"));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("resetxp", "Reset someone's or everyone's XP to 0.", (T context, [User? user]) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final m = await context.respond(MessageBuilder(content: "XP levels are being reset for ${(user != null ? (await memberFromUserToString(user, client: context.client, guild: context.guild)) : null) ?? "everyone"}, please wait..."));
      final List<User> users = user != null ? [user] : (await getAllMembers(context.guild!)).map((x) => x.user).whereType<User>().toList();

      if (users.isEmpty) {
        await context.updateMessage(m, MessageUpdateBuilder(content: "No users found."));
        return;
      }

      for (int i = 0; i < users.length; i++) {
        try {
          final member = users[i];
          if (isXpBanned(settings, member)) continue;
          final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, member.id);

          if (userSettings.xp.get() != null) {
            userSettings.xp.set(0);
          }
        } catch (e) {
          final member = users[i];
          Logger.warn("ResetXP", "Error with user $i (${member.id}): $e");
        }
      }

      await context.updateMessage(m, MessageUpdateBuilder(content: "Process complete! Run `reassignxp` to reassign levels.\n-# Target: ${(user != null ? (await memberFromUserToString(user, client: context.client, guild: context.guild)) : null) ?? "everyone"}"));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("setxp", "Set someone's XP level.", (T context, User user, double amount) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      if (!xpEnabled(settings)) return context.respondWithError("The XP system is disabled.");
      final member = await userToMember(user, guild: context.guild);

      final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, user.id);
      userSettings.xp.set(amount);
      await evalXpRoles(guild: context.guild!, member: member, xp: amount);
      await context.respond(MessageBuilder(content: "Set ${await memberToString(member, client: context.client)}'s XP to **$amount**."));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("addxp", "Add to someone's XP.", (T context, User user, double amount, [bool overrideXpPerHour = true]) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      if (!xpEnabled(settings)) return context.respondWithError("The XP system is disabled.");

      final added = await addXp(null, context.guild!, user, amount, overrideXpPerHour: overrideXpPerHour, client: context.client);
      await context.respond(MessageBuilder(content: ["Added ${added?.added ?? 0} XP to ${await memberFromUserToString(user, guild: context.guild, client: context.client)}'s XP.", if (added?.newRole != null) "New role: **${added!.newRole!.name}**"].join("\n")));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("pingonlevelup", "Set if the bot should ping on XP level up.", (T context, bool value) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      settings.pingOnLevelUp.set(value);
      await context.respond(MessageBuilder(content: "The bot ${value ? "**will**" : "will **not**"} ping on level up."));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("xpban", "Ban a user from the XP system.", (T context, User user) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final current = settings.xpBanned.get() ?? [];
      current.add(user.id);
      settings.xpBanned.set(current);

      await context.respond(MessageBuilder(
        content: "${await memberFromUserToString(user, guild: context.guild, client: context.client)} has been **banned** from the XP system.",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("xpunban", "Unban a user from the XP system.", (T context, User user) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final current = settings.xpBanned.get() ?? [];
      current.removeWhere((x) => x == user.id);
      settings.xpBanned.set(current);

      await context.respond(MessageBuilder(
        content: "${await memberFromUserToString(user, guild: context.guild, client: context.client)} has been **unbanned** from the XP system.",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("isxpbanned", "Get if a user is banned from the XP system.", (T context, [User? user]) async {
      user ??= context.member?.user ?? (context.member != null ? await context.client.users.get(context.member!.id) : null);
      if (context.guild == null || user == null) return context.respondWithError("No guild/member found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);

      final current = settings.xpBanned.get() ?? [];
      final banned = current.any((x) => x == user!.id);

      await context.respond(MessageBuilder(
        content: "${await memberFromUserToString(user, guild: context.guild, client: context.client)} is currently **${banned ? "banned" : "unbanned"}** from the XP system.",
      ));
    }, CommandAttributes(category: "XP")),

    BotCommand.command("xpenable", "Enable/disable the XP system.", (T context, [bool enabled = true]) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      settings.xpEnabled.set(enabled);

      await context.respond(MessageBuilder(
        content: ["The XP system has been **${enabled ? "enabled" : "disabled"}**.", if (!enabled) "-# To clear everyone's roles, run `resetxp`, then `reassignxp`."].join("\n"),
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("xpenabled", "See if the XP system is enabled.", (T context) async {
      if (context.guild == null) return context.respondWithError("No guild found.");
      final settings = Calebh101BotServerSettings(store, context.guild!.id);
      final enabled = settings.xpEnabled.get() ?? false;

      await context.respond(MessageBuilder(
        content: "The XP system is **${enabled ? "enabled" : "disabled"}**.",
      ));
    }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

    BotCommand.command("stats", "See your stats, or somebody else's.", (T context, [Member? member]) async {
      member ??= context.member;
      if (member == null || context.guild == null) return context.respondWithError("No guild/member found.");
      final guild = context.guild!;
      final avatar = member.avatar ?? member.user?.avatar;

      final serverSettings = Calebh101BotServerSettings(store, guild.id);
      final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
      final String level = (await getRole(guild, Snowflake(levelFromXp(serverSettings.xpLevels.get() ?? [], getRoundedXp(settings))?.roleId ?? 0)))?.toMention() ?? "Member";

      List<String> properties = [
        if (guild.ownerId == member.id) "Server Owner",
        if (isAdmin(settings: serverSettings, member: member)) "Bot Admin",
        if (isClaimer(settings: serverSettings, id: member.id)) "Bot Claimer",
        if (isOwner(id: member.id)) "Bot Owner",
      ];

      await context.respond(MessageBuilder(
        embeds: [
          EmbedBuilder(
            title: "Stats for ${await memberToString(member, client: context.client)}",
            color: (await getPrimaryColor(member)) ?? primaryBotColor,
            timestamp: DateTime.now().toUtc(),
            fields: [
              EmbedFieldBuilder(name: "XP", value: getRoundedXp(settings).toString(), isInline: true),
              EmbedFieldBuilder(name: "Level", value: level, isInline: true),
              EmbedFieldBuilder(name: "Joined On", value: "${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.longDateTime)} (${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.relative)})", isInline: false),
              if (properties.isNotEmpty) EmbedFieldBuilder(name: "Properties", value: properties.join(", "), isInline: false),
            ],
            footer: isAdmin(settings: serverSettings, member: context.member!) ? EmbedFooterBuilder(text: "Exact XP: ${settings.xp.get()}") : null,
            thumbnail: avatar != null ? EmbedThumbnailBuilder(url: avatar.url) : null,
          ),
        ],
      ));
    }, CommandAttributes(category: "User")),

    BotCommand("aboutxp", "XP", "See info about the XP system.", (T context) async {
      final settings = ifGuild(store, context.guild?.id, (id) => Calebh101BotServerSettings(store, id));
      final levels = settings?.xpLevels.get()?.nullIfEmpty;

      final content = """
The XP system is a system to show how active you are in the community.
The way it works, is you get XP from each message you send and reaction you add. You can either save this up, or you can gamble it away with the `gamble` command for a chance to win big!

- XP per message: up to **${xpPerMessage(2000)} XP**
- XP per reaction $xpPerReaction XP**
- Max XP per hour: **$maxXpPerHour XP**

${levels != null ? "You can also get these roles from getting XP:\n\n${levels.map((level) {
  return "- ${level.roleId.toRoleMention()}: **${level.requiredXp}** XP";
}).join("\n")}""\n\n" : ""}
""".trim();

      await context.respond(MessageBuilder(content: content, allowedMentions: AllowedMentions(repliedUser: true)));
    }),

    BotCommand("xpignoredchannels", "XP", "Get all channels where XP is *not* added.", (T context) async {
      final settings = Calebh101BotServerSettings(store, context.guildId!);
      final ids = settings.xpIgnoredChannels.get();

      await context.respond(MessageBuilder(content: ids.nullIfEmpty?.map((id) {
        return "- ${id.value.toChannel()} (`$id`)";
      }).join("\n") ?? "No channels ignored."));
    }, needsGuild: true),

    BotCommand("addxpignoredchannels", "XP", "Add channels where XP is *not* added.", (T context, GreedyGuildTextChannelList channels) async {
      final settings = Calebh101BotServerSettings(store, context.guildId!);
      final ids = settings.xpIgnoredChannels.get();

      ids.addAll(channels.data.map((x) => x.id));
      settings.xpIgnoredChannels.set(ids);
      await context.respond(MessageBuilder(content: "Added ${channels.data.map((x) => x.toMention()).join(", ")}."));
    }, needsGuild: true, permissionsRequired: .admin, aliases: ["addxpignoredchannel"]),

    BotCommand("removexpignoredchannels", "XP", "Remove channels where XP is *not* added.", (T context, GreedyGuildTextChannelList channels) async {
      final settings = Calebh101BotServerSettings(store, context.guildId!);
      final ids = settings.xpIgnoredChannels.get();

      ids.removeWhere((x) => channels.data.any((y) => x == y.id));
      settings.xpIgnoredChannels.set(ids);
      await context.respond(MessageBuilder(content: "Removed ${channels.data.map((x) => x.toMention()).join(", ")}."));
    }, needsGuild: true, permissionsRequired: .admin, aliases: ["removexpignoredchannel"]),

    BotCommand("resetxpignoredchannels", "XP", "Reset all channels where XP is *not* added.", (T context) async {
      final settings = Calebh101BotServerSettings(store, context.guildId!);
      settings.xpIgnoredChannels.delete();
      await context.respond(MessageBuilder(content: "Reset ignored channels."));
    }, needsGuild: true, permissionsRequired: .admin),
  ];

  bool checkIsValidForXp(User? user) {
    if (user == null) return false;
    if (user.isBot) return false;
    if (user.isSystem) return false;
    return true;
  }

  bool isXpBanned(Calebh101BotServerSettings settings, User member) {
    final list = settings.xpBanned.get() ?? [];
    return list.any((x) => x == member.id);
  }

  bool xpEnabled(Calebh101BotServerSettings settings) {
    return settings.xpEnabled.get() ?? false;
  }

  Future<void> evalXpRoles({required Guild guild, required Member? member, required double xp}) async {
    final settings = Calebh101BotServerSettings(store, guild.id);
    final qualifiedRoleIds = levelsFromXp(settings.xpLevels.get() ?? [], roundXp(xp)).map((x) => x.roleId).toSet();

    for (final XPLevel x in settings.xpLevels.get() ?? []) {
      if (member == null) continue;
      final role = await getRole(guild, Snowflake(x.roleId));
      if (role == null) continue;
      final shouldHave = qualifiedRoleIds.contains(x.roleId);
      final has = member.roleIds.contains(role.id);
      if (shouldHave && !has) {
        await member.addRole(role.id);
      } else if (!shouldHave && has) {
        await member.removeRole(role.id);
      }
    }
  }

  Future<AddXPResult?> addXp(GatewayEvent? event, Guild guild, User user, double toAdd, {bool overrideXpPerHour = false, required NyxxGateway client}) async {
    final serverSettings = Calebh101BotServerSettings(store, guild.id);
    if (!xpEnabled(serverSettings)) return null;
    if (isXpBanned(serverSettings, user)) return null;

    final settings = Calebh101BotUserPerServerSettings(store, guild.id, user.id);
    final value = settings.xp.get() ?? 0;

    if (!overrideXpPerHour) {
      if (settings.lastXpHour.get() == getHour()) {
        final xpThisHour = settings.xpThisHour.get() ?? 0;
        if (xpThisHour >= maxXpPerHour) return null;

        if (xpThisHour + toAdd > maxXpPerHour) toAdd = maxXpPerHour - xpThisHour;
        settings.xpThisHour.set(xpThisHour + toAdd);
      } else {
        if (toAdd > maxXpPerHour) toAdd = maxXpPerHour;
        settings.lastXpHour.set(getHour());
        settings.xpThisHour.set(toAdd);
      }
    }

    final newValue = value + toAdd;
    settings.xp.set(newValue);

    final oldLevel = levelFromXp(serverSettings.xpLevels.get() ?? [], roundXp(value));
    final newLevel = levelFromXp(serverSettings.xpLevels.get() ?? [], roundXp(newValue));
    final oldRole = oldLevel != null ? await getRole(guild, Snowflake(oldLevel.roleId)) : null;
    final newRole = newLevel != null ? await getRole(guild, Snowflake(newLevel.roleId)) : null;
    final levelUp = toAdd > 0 && oldLevel?.roleId != newLevel?.roleId && newLevel != null;
    final member = await userToMember(user, guild: guild);

    await evalXpRoles(guild: guild, member: member, xp: newValue);

    Modlog.add(ModlogEvent(
      "xp.add",
      settings: serverSettings,
      guild: guild,
      client: client,
      title: "XP Added",
      fields: {
        "Receiver": "<@${user.id}>",
        "Event": event.runtimeType.toDiscordCodeString(),
        "XP": "$value + $toAdd = $newValue".toDiscordCodeBlock(),
        "Level Up": levelUp ? "${oldLevel?.roleId} (${oldRole?.name}) => ${newLevel.roleId} (${newRole?.name})".toDiscordCodeBlock() : null.toDiscordCodeString(),
      },
      alsoTriggerOn: [if (levelUp) "xp.levelup"],
      severity: .verbose,
    ));

    if (levelUp && member != null) {
      try {
        final ping = serverSettings.pingOnLevelUp.get() ?? true;
        final channelId = serverSettings.xpChannel.get();
        final channel = channelId != null ? await client.channels.get(Snowflake(channelId)) : null;

        if (channel is GuildTextChannel) {
          await channel.sendMessage(MessageBuilder(
            content: ping ? user.toMention() : null,
            embeds: [
              EmbedBuilder(
                description: "## ${user.toMention()} has leveled up to ${newLevel.roleId.toRoleMention()}!",
                thumbnail: member.avatar?.url != null ? EmbedThumbnailBuilder(url: member.avatar!.url) : null,
                color: await getPrimaryColor(member) ?? primaryBotColor,
              ),
            ],
          ));
        }
      } catch (e) {
        Logger.warn("addXp", "Unable to find channel: $e");
      }
    }

    return AddXPResult(added: toAdd, levelUp: levelUp, oldLevel: oldLevel, newLevel: newLevel, oldRole: oldRole, newRole: newRole);
  }

  int getRoundedXp(Calebh101BotUserPerServerSettings settings) {
    return roundXp(settings.xp.get() ?? 0);
  }

  int roundXp(double xp) {
    return xp.floor();
  }

  XPLevel? levelFromXp(List<XPLevel> levels, int xp) {
    levels.sort((a, b) => b.requiredXp.compareTo(a.requiredXp));

    for (final level in levels) {
      if (xp >= level.requiredXp) {
        return level;
      }
    }

    return null;
  }

  List<XPLevel> levelsFromXp(List<XPLevel> levels, int xp) {
    final sorted = List<XPLevel>.from(levels)..sort((a, b) => b.requiredXp.compareTo(a.requiredXp));
    return sorted.where((level) => xp >= level.requiredXp).toList();
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) => client.onMessageCreate.listen((event) async {
      if (isIgnored(store, event.message.author.id)) return;
      final guild = await event.guild?.get();
      final user = await client.users.get(event.message.author.id);
      if (guild == null || !checkIsValidForXp(user)) return;

      final serverSettings = Calebh101BotServerSettings(store, guild.id);
      final prefix = serverSettings.prefix.get();
      final u = client.user.id;

      final isValidContent = !event.message.content.startsWith(prefix) && !event.message.content.startsWith("<@$u>") && !serverSettings.xpIgnoredChannels.get().contains(event.message.channelId);
      if (isValidContent) addXp(event, guild, user, xpPerMessage.call(event.message.content.length), client: event.gateway.client);
    }));

    context.clients.run((client) => client.onMessageReactionAdd.listen((event) async {
      if (isIgnored(store, event.userId)) return;
      final guild = await event.guild?.get();
      final user = await event.user.get();

      if (guild == null) return;
      final serverSettings = Calebh101BotServerSettings(store, guild.id);
      if (!checkIsValidForXp(user) || !serverSettings.xpIgnoredChannels.get().contains(event.channelId)) return;

      addXp(event, guild, user, xpPerReaction, client: event.gateway.client);
    }));

    context.clients.run((client) => client.onGuildMemberAdd.listen((event) async {
      if (isIgnored(store, event.member.id)) return;
      final settings = Calebh101BotUserPerServerSettings(store, event.guildId, event.member.id);
      await evalXpRoles(guild: await event.guild.get(), member: event.member, xp: settings.xp.get() ?? 0);
    }));
  }
}

class AddXPResult {
  final double added;
  final bool levelUp;

  final XPLevel? oldLevel;
  final XPLevel? newLevel;
  final Role? oldRole;
  final Role? newRole;

  const AddXPResult({required this.added, required this.levelUp, required this.oldLevel, required this.newLevel, required this.oldRole, required this.newRole});
}

@JsonSerializable(anyMap: true)
class XPLevel {
  final int roleId;
  int requiredXp;

  XPLevel({required this.requiredXp, required this.roleId});
  factory XPLevel.fromJson(Map input) => _$XPLevelFromJson(input);
  Map toJson() => _$XPLevelToJson(this);
}