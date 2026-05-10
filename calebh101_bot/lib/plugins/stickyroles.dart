import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class StickyRoles extends BotPluginLegacy {
  StickyRoles() : super(id: "stickyroles", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("addrole", "Moderation", "Add a sticky role to someone.", (ChatContext context, Member member, Role role, [bool sticky = true]) async {
        if (await context.assureGuild() == false) return;
        final settings = StickyRolesSettings(store, context.guild!.id, member.id);

        try {
          await member.addRole(role.id);
        } catch (e) {
          Logger.warn("StickyRoles", "Unable to add role ${role.id}: $e");
          return context.respondWithError("We couldn't add role ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}.");
        }

        if (sticky) {
          final current = settings.stickyRoles.get() ?? [];
          current.add(role.id.value);
          settings.stickyRoles.set(current);
        }

        await context.respond(MessageBuilder(content: "Added ${sticky ? "sticky role" : "role"} ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}!"));
      }, permissionsRequired: BotCommandPermissions.admin, aliases: ["r+"]),
      BotCommand("remrole", "Moderation", "Remove a role from someone.", (ChatContext context, Member member, Role role) async {
        if (await context.assureGuild() == false) return;
        final settings = StickyRolesSettings(store, context.guild!.id, member.id);

        final current = settings.stickyRoles.get() ?? [];
        current.removeWhere((x) => x == role.id.value);
        settings.stickyRoles.set(current);

        try {
          await member.removeRole(role.id);
        } catch (e) {
          Logger.warn("StickyRoles", "Unable to remove role ${role.id}: $e");
          return context.respondWithError("We couldn't remove role ${await roleToString(role)} from user ${await memberToString(member, client: context.client)}.");
        }

        await context.respond(MessageBuilder(content: "Removed role ${await roleToString(role)} from user ${await memberToString(member, client: context.client)}!"));
      }, permissionsRequired: BotCommandPermissions.admin, aliases: ["r-"]),
      BotCommand("stickyroles", "StickyRole", "List someone's current sticky roles.", (ChatContext context, Member member) async {
        if (await context.assureGuild() == false) return;
        final settings = StickyRolesSettings(store, context.guild!.id, member.id);
        final current = settings.stickyRoles.get() ?? [];

        await context.respond(MessageBuilder(content: "Current sticky roles for user ${await memberToString(member, client: context.client)}:\n\n${(await Future.wait(current.map((x) async {
          final role = await () async {
            try {
              return await context.guild!.roles.get(Snowflake(x));
            } catch (e) {
              Logger.warn("StickyRoles", "Unable to get role $x: $e");
            }
          }();

          return "- ${role != null ? "${await roleToString(role)}" : "`<no role found>`"} (${x.toDiscordCodeString()})";
        }))).join("\n")}"));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("evalstickyroles", "StickyRole", "List someone's current sticky roles.", (ChatContext context, Member member) async {
        if (await context.assureGuild() == false) return;
        final results = await eval(store: store, guild: context.guild!, member: member, client: context.client, author: context.user);
        await context.respond(MessageBuilder(content: "Current sticky roles for user ${await memberToString(member, client: context.client)}:\n\n${results.join("\n")}"));
      }, permissionsRequired: BotCommandPermissions.admin),
    ];
  }

  Future<List<String>> eval({required KVStore store, required Guild guild, required Member member, required NyxxGateway client, User? author}) async {
    final settings = StickyRolesSettings(store, guild.id, member.id);
    final current = settings.stickyRoles.get() ?? [];

    if (current.isEmpty) return [];
    List<int> success = [];

    for (final id in current) {
      try {
        await member.addRole(Snowflake(id));
        success.add(id);
      } catch (e) {
        Logger.warn("StickyRoles", "Unable to add role: $id");
      }
    }

    final all = await Future.wait(current.map((x) async {
      final role = await () async {
        try {
          return await guild.roles.get(Snowflake(x));
        } catch (e) {
          Logger.warn("StickyRoles", "Unable to get role $x: $e");
        }
      }();

      return "- ${role != null ? "${await roleToString(role)}" : "`<no role found>`"} (${x.toDiscordCodeString()}): **${success.contains(x) ? "Success" : "Fail"}**";
    }));

    Modlog.add(ModlogEvent(
      "stickyrole.eval",
      guild: guild,
      client: client,
      settings: ServerSettings(store, guild.id),
      title: "Sticky Roles Evaluated",
      fields: {
        "Who": member.toMention(),
        "Author": ?author?.toMention(),
        "Results": "**${current.length}** found, **${success.length}** success",
        "Output": all.join("\n").toDiscordCodeBlock(),
      },
    ));

    return all;
  }

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [
      {
        ModlogGroup.all: (levelBelow) => {...levelBelow},
        ModlogGroup.normal: (levelBelow) => {...levelBelow, "stickyrole.eval"},
        ModlogGroup.quiet: (levelBelow) => {...levelBelow},
        ModlogGroup.off: (_) => {},
      },
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        await eval(store: context.store, guild: await event.guild.get(), member: event.member, client: client);
      });
    });
  }
}

class StickyRolesSettings extends UserPerServerSettings {
  StickyRolesSettings(super.store, super.server, super.user);

  SettingsObject<List<int>> get stickyRoles => SettingsObject.list<int>(this, "sr");
}