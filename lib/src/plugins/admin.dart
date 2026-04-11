import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class AdminPlugin extends BotPlugin {
  AdminPlugin() : super(id: "admin", name: "Admin Commands", version: Version.parse("1.0.0A"));

  @override
  List<BotCommand> commands(CommandsPlugin plugin, KVStore store) {
    return adminCommands(store);
  }

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [{
      ModLogGroup.all: (levelBelow) => {...levelBelow},
      ModLogGroup.normal: (levelBelow) => {...levelBelow},
      ModLogGroup.quiet: (levelBelow) => {...levelBelow, "adminuser.add", "adminuser.remove", "adminrole.add", "adminrole.remove", "claim"},
      ModLogGroup.off: (_) => {},
    }];
  }

  List<BotCommand> adminCommands(KVStore store) => [
    BotCommand.command("addadminuser", "Add an admin user.", (ChatContext context, User user) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
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
        client: context.client,
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
      final settings = ServerSettings(store, context.guild!.id);
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
        client: context.client,
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
      final settings = ServerSettings(store, context.guild!.id);
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
        client: context.client,
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
      final settings = ServerSettings(store, context.guild!.id);
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
        client: context.client,
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
      final settings = ServerSettings(store, context.guild!.id);
      if (context.member == null) return context.respondWithError("No member found.");
      final mainAdmin = settings.mainAdmin.get();

      if (mainAdmin == null || isOwner(id: context.member!.id)) {
        settings.mainAdmin.set(context.member!.id.toString());

        Modlog.add(ModlogEvent(
          "claim",
          guild: context.guild,
        client: context.client,
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
            await m.edit(MessageUpdateBuilder(content: "I have been reclaimed by ${await memberToString(context.member, client: context.client)}.\n-# I was claimed by ${await memberToString(member, client: context.client)}."));
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
          m.edit(MessageUpdateBuilder(content: "I've already been claimed by ${await memberToString(member, client: context.client)}."));
        } catch (e) {
          Logger.warn("Commands.Claim", "User $mainAdmin not found: $e");
        }
      }
    }, CommandAttributes(category: "Bot")),
    BotCommand.command("unclaim", "Step down as king of the bot. This will not be made known to others.", (ChatContext context) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
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
        client: context.client,
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
          await m.edit(MessageUpdateBuilder(content: "I have been unclaimed.\n-# I was claimed by ${await memberToString(member, client: context.client)}."));
        } catch (e) {
          Logger.warn("Commands.Unclaim", "User $old not found: $e");
        }
      }
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.claimer, category: "Bot")),
    BotCommand.command("owner", "See stats about who owns the bot, who owns the server, and who's claimed the bot.", (ChatContext context) async {
      final settings = context.guild == null ? null : ServerSettings(store, context.guild!.id);
      final mainAdmin = settings?.mainAdmin.get();
      Map<String, String> results = {};

      if (globalOwner != null) {
        results["Bot Owner"] = "**${globalOwner!.name}** (*${globalOwner!.username}*)";
      }

      if (mainAdmin != null) {
        try {
          final member = await context.guild!.members.get(Snowflake(int.parse(mainAdmin)));
          results["Bot Claimer"] = (await memberToString(member, client: context.client))!;
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
          results["Server Owner"] = (await memberToString(serverOwner, client: context.client))!;
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
    BotCommand.command("attributes", "See your attributes.", (ChatContext context, [@Description('The member to check') Member? member]) async {
      final m = member ?? context.member;
      final u = m?.user ?? context.user;
      List<String> attributes = ["Alive"];

      if (context.guild != null && context.member != null) {
        attributes.add("In *${context.guild!.name}*");
        final settings = ServerSettings(store, context.guild!.id);

        if (true /* Was: settings != null */) {
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
          content: "### Attributes for ${await userOrMemberToString(m, u, client: context.client)}${context.guild != null ? " in *${context.guild!.name}*" : ""}\n\n${attributes.map((x) => "- $x").join("\n")}",
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
}