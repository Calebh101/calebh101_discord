import 'dart:math';

import 'package:calebh101_bot/types.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

final double xpPerReaction = 0.01;
final double Function(String content) xpPerMessage = (content) => min(content.length / 1000, 0.2); // Message length of 200+ => 0.2, 20 => 0.02, 2 => 0.02

final store = KVStore("database.db");

void main(List<String> arguments) async {
  Modlog({
    ModLogGroup.all: (levelBelow) => {...levelBelow, "xp.add"},
    ModLogGroup.normal: (levelBelow) => {...levelBelow, "xp.levelup"},
    ModLogGroup.quiet: (levelBelow) => levelBelow,
  });

  final context = await load(
    botName: "Caleb-Bot",
    version: Version.parse("0.0.0A"),

    owner: calebh101,
    supportServer: calebh101Server,

    primaryColor: DiscordColor.parseHexString("#00FFF0"),
    prefix: mentionOr(prefixFromServerSettings((x) => Calebh101BotServerSettings(store, x.id))),
    permissions: [...GatewayIntents.all],

    store: store,
    settings: BotSettings(),

    commands: (plugin) => [
      BotCommand.converter((plugin) => plugin.getConverter(RuntimeType<GuildTextChannel>(), logWarn: false)),

      pingCommand(),
      messageMe(),
      aboutCommand(store),

      helpCommand((x) => Calebh101BotServerSettings(store, x.id), plugin),
      listAllServerSettings((x) => Calebh101BotServerSettings(store, x.id)),
      killCommand((x) => Calebh101BotServerSettings(store, x.id)),
      echoDebugCommand((x) => Calebh101BotServerSettings(store, x.id)),
      deleteMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),

      ...adminRoles((x) => Calebh101BotServerSettings(store, x.id)),
      ...modLogCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...prefixCommands((x) => Calebh101BotServerSettings(store, x.id)),

      BotCommand.command("stats", "See your stats, or somebody else's.", (ChatContext context, [Member? member]) async {
        member ??= context.member;
        if (member == null || context.guild == null) return context.respondWithError("No guild/member found.");
        final guild = context.guild!;

        final serverSettings = Calebh101BotServerSettings(store, guild.id);
        final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
        final String level = getRole(guild, Snowflake(levelFromXp(serverSettings.xpLevels.get() ?? [], getRoundedXp(settings))?.roleId ?? 0))?.toMention() ?? "Member";

        List<String> properties = [
          if (guild.ownerId == member.id) "Server Owner",
          if (isAdmin(settings: serverSettings, id: member.id)) "Bot Admin",
          if (isClaimer(settings: serverSettings, id: member.id)) "Bot Claimer",
          if (isOwner(id: member.id)) "Bot Owner",
        ];

        await context.respond(MessageBuilder(
          embeds: [
            EmbedBuilder(
              title: "Stats for ${await memberToString(member)}",
              color: (await getPrimaryColor(member)) ?? primaryBotColor,
              timestamp: DateTime.now(),
              fields: [
                EmbedFieldBuilder(name: "XP", value: getRoundedXp(settings).toString(), isInline: true),
                EmbedFieldBuilder(name: "Level", value: level, isInline: true),
                EmbedFieldBuilder(name: "Join Position", value: "${await getJoinPosition(guild, member) + 1} / ${(await guild.fetchPreview()).approximateMemberCount}", isInline: false),
                EmbedFieldBuilder(name: "Joined On", value: "${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.longDateTime)} (${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.relative)})", isInline: false),
                if (properties.isNotEmpty) EmbedFieldBuilder(name: "Properties", value: properties.join(", "), isInline: false),
              ],
              footer: isAdmin(settings: serverSettings, id: context.user.id) ? EmbedFooterBuilder(text: "Exact XP: ${settings.xp.get()}") : null,
            ),
          ],
        ));
      }, CommandAttributes(category: "User")),

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

      BotCommand.command("reassignxp", "Remove an XP level by name.", (ChatContext context) async {
        if (context.guild == null) return context.respondWithError("No guild found.");
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
        final members = await getAllMembers(context.guild!);

        String getMessage(int progress) {
          return "XP levels are being reassigned, please wait...\n-# Progress: $progress%";
        }

        final m = await context.respond(MessageBuilder(
          content: getMessage(0),
        ));

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

            if (i % 100 == 1) {
              if (context is InteractionChatContext) {
                await context.interaction.updateOriginalResponse(MessageUpdateBuilder(content: getMessage(((i + 1) / members.length).floor())));
              } else {
                await m.update(MessageUpdateBuilder(content: getMessage(((i + 1) / members.length).floor())));
              }
            }
          } catch (e) {
            final member = members[i];
            Logger.warn("ReassignXP", "Error with user $i (${member.id}): $e");
          }

          if (context is InteractionChatContext) {
            await context.interaction.updateOriginalResponse(MessageUpdateBuilder(content: "Process complete!"));
          } else {
            await m.update(MessageUpdateBuilder(content: "Process complete!"));
          }
        }
      }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),

      BotCommand.command("setxp", "Set someone's XP level.", (ChatContext context, Member member, double amount) async {
        if (context.guild == null) return context.respondWithError("No guild found.");
        final settings = Calebh101BotServerSettings(store, context.guild!.id);
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

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
        await context.respond(MessageBuilder(content: "Set ${await memberToString(member)}'s XP to **$amount**.\nNew role: ${newRole?.name ?? null.toDiscordCodeString()}"));
      }, CommandAttributes(category: "XP", permissionsRequired: BotCommandPermissions.admin)),
    ],
  );

  if (context == null) return;
  Logger.print("main", "Bot loaded!");

  context.client.onMessageCreate.listen((event) async {
    final guild = await event.guild?.get();
    final member = await event.member?.get();

    if (guild == null || !checkIsValidForXp(member)) return;
    addXp(event, guild, member!, xpPerMessage.call(event.message.content));
  });

  context.client.onMessageReactionAdd.listen((event) async {
    final guild = await event.guild?.get();
    final member = await event.member?.get();

    if (guild == null || !checkIsValidForXp(member)) return;
    addXp(event, guild, member!, xpPerReaction);
  });
}

bool checkIsValidForXp(Member? member) {
  if (member == null) return false;
  if (member.user?.isBot ?? true) return false;
  if (member.user?.isSystem ?? true) return false;
  return true;
}

Future<void> addXp(GatewayEvent event, Guild guild, Member member, double toAdd) async {
  final serverSettings = Calebh101BotServerSettings(store, guild.id);
  final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
  final value = settings.xp.get() ?? 0;
  final newValue = value + toAdd;
  settings.xp.set(newValue);

  final oldLevel = levelFromXp(serverSettings.xpLevels.get() ?? [], roundXp(value));
  final newLevel = levelFromXp(serverSettings.xpLevels.get() ?? [], roundXp(newValue));
  final oldRole = oldLevel != null ? getRole(guild, Snowflake(oldLevel.roleId)) : null;
  final newRole = newLevel != null ? getRole(guild, Snowflake(newLevel.roleId)) : null;
  final levelUp = oldLevel?.roleId != newLevel?.roleId && newLevel != null;

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
}

int getRoundedXp(Calebh101BotUserPerServerSettings settings) {
  return roundXp(settings.xp.get() ?? 0);
}

int roundXp(double xp) {
  return xp.floor();
}

Future<int> getJoinPosition(Guild guild, Member member) async {
  final members = await getAllMembers(guild)..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
  final index = members.indexWhere((m) => m.id == member.id);
  return index;
}

Future<List<Member>> getAllMembers(Guild guild, {int limitPer = 1000}) async {
  List<Member> result = [];

  while (true) {
    try {
      final members = await guild.members.list(limit: limitPer, after: result.lastOrNull?.id);
      Logger.print("getAllMembers", "Found ${members.length} (${result.length} existing)");
      if (members.isEmpty) break;
      result.addAll(members);
    } catch (e) {
      Logger.warn("getAllMembers", "Error: $e (${result.length} existing)");
      break;
    }
  }

  return result;
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

Role? getRole(Guild guild, Snowflake id) {
  return guild.roleList.firstWhereOrNull((y) => y.id == id);
}

class Calebh101BotServerSettings extends ServerSettings {
  SettingsObject<List<XPLevel>> get xpLevels => SettingsObject(this, "levels", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => XPLevel.fromJson(x)).toList());

  Calebh101BotServerSettings(super.store, super.id);
}

class Calebh101BotUserSettings extends UserSettings {
  Calebh101BotUserSettings(super.store, super.id);
}

class Calebh101BotUserPerServerSettings extends UserPerServerSettings {
  SettingsObject<double> get xp => SettingsObject(this, "xp");

  Calebh101BotUserPerServerSettings(super.store, super.server, super.user);
}