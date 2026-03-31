import 'dart:math';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_bot/types.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

List<BotCommand> xpCommands(KVStore store) => [
  BotCommand.command("leaderboard", "Get the current XP leaderboard.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (settings.xpEnabled.get() != true) return context.respondWithError("XP is not enabled.");
    final banned = settings.xpBanned.get() ?? [];

    final values = store.getAllForKey<double>(Scope.userPerServer, "xp").entries
      .where((x) {
        final ids = UserPerServerSettings.parseId(x.key);
        if (ids.server != context.guild!.id) return false;
        if (banned.contains(ids.user)) return false;
        if (x.value <= 0) return false;
        return true;
      }).map((x) => MapEntry(UserPerServerSettings.parseId(x.key).user, x.value)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    const int maxLinesPerPage = 20;
    List<(int i, List<String>)> pages = [];
    List<String> currentPage = [];
    int currentPageLength = 0;

    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      final Role? level = getRole(context.guild!, Snowflake(levelFromXp(settings.xpLevels.get() ?? [], getRoundedXp(Calebh101BotUserPerServerSettings(store, context.guild!.id, v.key)))?.roleId ?? 0));

      currentPage.add([(v.key.value.toMention()), "**${roundXp(v.value)}** XP", ?level?.toMention()].join(" "));
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

  BotCommand.command("gamble", "Gamble your XP away.", (ChatContext context, double amountToBet) async {
    final member = context.member;
    final guild = context.guild;

    if (member == null || guild == null) return context.respondWithError("No guild/member found.");
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
      await addXp(null, guild, member, payout.toDouble());
      await context.respond(MessageBuilder(content: "${await memberToString(member)} bet **$amount** and **won** ${roundXp(payout.toDouble())} XP! That puts them at **${roundXp(current + payout)}** XP."));
    } else {
      await addXp(null, guild, member, -amount.toDouble());
      await context.respond(MessageBuilder(content: "${await memberToString(member)} bet **$amount** and *lost*. That puts them at **${roundXp(current - amount)}** XP."));
    }
  }, CommandAttributes(category: "XP", extendedDescription: "- Each bet has to be a multiple of 10.\n- The more you bet, the less chance you have to win.\n- ")),
  BotCommand.command("xplevels", "List all set XP levels.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    final roles = settings.xpLevels.get() ?? [];

    if (roles.isEmpty) {
      return context.respondWithError("No XP levels set.");
    }

    await context.respond(MessageBuilder(
      content: "## All XP Levels for *${context.guild!.name}*\n\n${roles.map((x) {
        return "- ${roleToString(getRole(context.guild!, Snowflake(x.roleId)))}: **${x.requiredXp}** XP required";
      }).join("\n")}",
    ));
  }, CommandAttributes(category: "XP")),

  BotCommand.command("addxplevel", "Add an XP level.", (ChatContext context, Role role, int requiredXp) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final roles = settings.xpLevels.get() ?? [];
    final level = XPLevel(requiredXp: requiredXp, roleId: role.id.value);
    roles.add(level);
    settings.xpLevels.set(roles);

    await context.respond(MessageBuilder(
      content: "Added XP level ${roleToString(role)} with **$requiredXp** XP!",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("editxplevel", "Add an XP level's required XP.", (ChatContext context, Role role, int requiredXp) async {
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
      content: "Set XP level ${roleToString(role)}'s required XP to **$requiredXp** XP.",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("removexplevel", "Remove an XP level by name.", (ChatContext context, Role role) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    var roles = settings.xpLevels.get() ?? [];
    roles = roles.where((x) => x.roleId != role.id.value).toList();
    settings.xpLevels.set(roles);

    await context.respond(MessageBuilder(
      content: "Removed XP level ${roleToString(role)}.",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("setxpupdateschannel", "Set a channel for the bot to announce updates like level-ups.", (ChatContext context, [GuildTextChannel? channel]) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    settings.xpChannel.set(channel?.id.value);
    await context.respond(MessageBuilder(content: "XP updates channel ${channel != null ? "to ${channel.toMention()}" : "removed"}!"));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("xpupdateschannel", "Get the channel for the bot to announce updates like level-ups.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);

    final id = settings.xpChannel.get();
    await context.respond(MessageBuilder(content: "XP updates channel ${id != null ? "is set to ${id.toChannel()}" : "not set"}."));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("reassignxp", "Reassign everyone's XP levels.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    String getMessage(int progress) {
      return "XP levels are being reassigned, please wait...\n-# Progress: $progress%";
    }

    final m = await context.respond(MessageBuilder(content: getMessage(0)));
    final members = await getAllMembers(context.guild!);

    for (int i = 0; i < members.length; i++) {
      try {
        final member = members[i];
        final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, member.id);
        final newLevel = levelFromXp(settings.xpLevels.get() ?? [], getRoundedXp(userSettings));
        final newRole = newLevel != null ? getRole(context.guild!, Snowflake(newLevel.roleId)) : null;

        for (final XPLevel x in settings.xpLevels.get() ?? []) {
          final role = getRole(context.guild!, Snowflake(x.roleId));
          if (role == null) continue;
          if (!member.roleIds.contains(role.id)) continue;
          await member.removeRole(role.id);
        }

        if (newRole != null) await member.addRole(newRole.id);

        if (i % 100 == 0) {
          await context.updateMessage(m, MessageUpdateBuilder(content: getMessage(((i + 1) / members.length).floor())));
        }
      } catch (e) {
        final member = members[i];
        Logger.warn("ReassignXP", "Error with user $i (${member.id}): $e");
      }
    }

    await context.updateMessage(m, MessageUpdateBuilder(content: "Process complete!"));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("resetxp", "Reset everyone's XP to 0.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final m = await context.respond(MessageBuilder(content: "XP levels are being reset, please wait..."));
    final members = await getAllMembers(context.guild!);

    for (int i = 0; i < members.length; i++) {
      try {
        final member = members[i];
        if (isXpBanned(settings, member)) continue;
        final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, member.id);

        if (userSettings.xp.get() != null) {
          userSettings.xp.set(0);
        }
      } catch (e) {
        final member = members[i];
        Logger.warn("ResetXP", "Error with user $i (${member.id}): $e");
      }
    }

    await context.updateMessage(m, MessageUpdateBuilder(content: "Process complete! Run `reassignxp` to reassign levels."));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("setxp", "Set someone's XP level.", (ChatContext context, Member member, double amount) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    if (!xpEnabled(settings)) return context.respondWithError("The XP system is disabled.");

    final userSettings = Calebh101BotUserPerServerSettings(store, context.guild!.id, member.id);
    userSettings.xp.set(amount);

    final newLevel = levelFromXp(settings.xpLevels.get() ?? [], roundXp(amount.toDouble()));
    final newRole = newLevel != null ? getRole(context.guild!, Snowflake(newLevel.roleId)) : null;

    for (final XPLevel x in settings.xpLevels.get() ?? []) {
      final role = getRole(context.guild!, Snowflake(x.roleId));
      if (role == null) continue;
      if (!member.roleIds.contains(role.id)) continue;
      await member.removeRole(role.id);
    }

    if (newRole != null) await member.addRole(newRole.id);
    await context.respond(MessageBuilder(content: "Set ${await memberToString(member)}'s XP to **$amount**.\nNew role: **${newRole?.name ?? null.toDiscordCodeString()}**"));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("addxp", "Add to someone's XP.", (ChatContext context, Member member, double amount, [bool overrideXpPerHour = true]) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    if (!xpEnabled(settings)) return context.respondWithError("The XP system is disabled.");

    final added = await addXp(null, context.guild!, member, amount, overrideXpPerHour: overrideXpPerHour);
    await context.respond(MessageBuilder(content: ["Added ${added?.added ?? 0} XP to ${await memberToString(member)}'s XP.", if (added?.newRole != null) "New role: **${added!.newRole!.name}**"].join("\n")));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("pingonlevelup", "Set if the bot should ping on XP level up.", (ChatContext context, bool value) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    settings.pingOnLevelUp.set(value);
    await context.respond(MessageBuilder(content: "The bot ${value ? "**will**" : "will **not**"} ping on level up."));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("xpban", "Ban a user from the XP system.", (ChatContext context, Member member) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final current = settings.xpBanned.get() ?? [];
    current.add(member.id);
    settings.xpBanned.set(current);

    await context.respond(MessageBuilder(
      content: "${await memberToString(member)} has been **banned** from the XP system.",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("xpunban", "Unban a user from the XP system.", (ChatContext context, Member member) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final current = settings.xpBanned.get() ?? [];
    current.removeWhere((x) => x == member.id);
    settings.xpBanned.set(current);

    await context.respond(MessageBuilder(
      content: "${await memberToString(member)} has been **unbanned** from the XP system.",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("isxpbanned", "Get if a user is banned from the XP system.", (ChatContext context, [Member? member]) async {
    member ??= context.member;
    if (context.guild == null || member == null) return context.respondWithError("No guild/member found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);

    final current = settings.xpBanned.get() ?? [];
    final banned = current.any((x) => x == member!.id);

    await context.respond(MessageBuilder(
      content: "${await memberToString(member)} is currently **${banned ? "banned" : "unbanned"}** from the XP system.",
    ));
  }, CommandAttributes(category: "XP")),

  BotCommand.command("xpenable", "Enable/disable the XP system.", (ChatContext context, [bool enabled = true]) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    settings.xpEnabled.set(enabled);

    await context.respond(MessageBuilder(
      content: ["The XP system has been **${enabled ? "enabled" : "disabled"}**.", if (!enabled) "-# To clear everyone's roles, run `resetxp`, then `reassignxp`."].join("\n"),
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

  BotCommand.command("xpenabled", "See if the XP system is enabled.", (ChatContext context) async {
    if (context.guild == null) return context.respondWithError("No guild found.");
    final settings = Calebh101BotServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
    final enabled = settings.xpEnabled.get() ?? false;

    await context.respond(MessageBuilder(
      content: "The XP system is **${enabled ? "enabled" : "disabled"}**.",
    ));
  }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),
];

bool checkIsValidForXp(Member? member) {
  if (member == null) return false;
  if (member.user?.isBot ?? true) return false;
  if (member.user?.isSystem ?? true) return false;
  return true;
}

bool isXpBanned(Calebh101BotServerSettings settings, Member member) {
  final list = settings.xpBanned.get() ?? [];
  return list.any((x) => x == member.id);
}

bool xpEnabled(Calebh101BotServerSettings settings) {
  return settings.xpEnabled.get() ?? false;
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

Future<AddXPResult?> addXp(GatewayEvent? event, Guild guild, Member member, double toAdd, {bool overrideXpPerHour = false}) async {
  final serverSettings = Calebh101BotServerSettings(store, guild.id);
  if (!xpEnabled(serverSettings)) return null;
  if (isXpBanned(serverSettings, member)) return null;

  final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
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
  final oldRole = oldLevel != null ? getRole(guild, Snowflake(oldLevel.roleId)) : null;
  final newRole = newLevel != null ? getRole(guild, Snowflake(newLevel.roleId)) : null;
  final levelUp = toAdd > 0 && oldLevel?.roleId != newLevel?.roleId && newLevel != null;

  for (final XPLevel x in serverSettings.xpLevels.get() ?? []) {
    final role = getRole(guild, Snowflake(x.roleId));
    if (role == null) continue;
    if (!member.roleIds.contains(role.id)) continue;
    await member.removeRole(role.id);
  }

  if (newRole != null) await member.addRole(newRole.id);

  Modlog.add(ModlogEvent(
    "xp.add",
    settings: serverSettings,
    guild: guild,
    title: "XP Added",
    fields: {
      "Receiver": "<@${member.id}>",
      "Event": event.runtimeType.toDiscordCodeString(),
      "XP": "$value + $toAdd = $newValue".toDiscordCodeBlock(),
      "Level Up": levelUp ? "${oldLevel?.roleId} (${oldRole?.name}) => ${newLevel.roleId} (${newRole?.name})".toDiscordCodeBlock() : null.toDiscordCodeString(),
    },
    alsoTriggerOn: [if (levelUp) "xp.levelup"],
  ));

  if (levelUp) {
    try {
      final ping = serverSettings.pingOnLevelUp.get() ?? true;
      final channelId = serverSettings.xpChannel.get();
      final channel = channelId != null ? await client.channels.get(Snowflake(channelId)) : null;

      if (channel is GuildTextChannel) {
        await channel.sendMessage(MessageBuilder(
          content: ping ? member.toMention() : null,
          embeds: [
            EmbedBuilder(
              description: "## ${member.toMention()} has leveled up to ${newLevel.roleId.toRoleMention()}!",
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