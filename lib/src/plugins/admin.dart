import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class AdminPlugin extends BotPluginLegacy {
  AdminPlugin() : super(id: "admin", version: Version.parse("1.0.0A"));

  @override
  List<BotCommand> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return adminCommands<T>(store);
  }

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [{
      ModlogGroup.all: (levelBelow) => {...levelBelow},
      ModlogGroup.normal: (levelBelow) => {...levelBelow},
      ModlogGroup.quiet: (levelBelow) => {...levelBelow, "adminuser.add", "adminuser.remove", "adminrole.add", "adminrole.remove", "moduser.add", "moduser.remove", "modrole.add", "modrole.remove", "claim"},
      ModlogGroup.off: (_) => {},
    }];
  }

  List<BotCommand> adminCommands<T extends ChatContext>(KVStore store) => [
    BotCommand.command("addadminuser", "Add an admin user.", (T context, User user) async {
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
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("addadminrole", "Add a role as admin.", (T context, Role role) async {
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
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("removeadminuser", "Remove a user from admin.", (T context, User user) async {
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
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("removeadminrole", "Remove a role from admin.", (T context, Role role) async {
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
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),

    BotCommand.command("addmoduser", "Add an admin user.", (T context, User user) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      final admins = settings.mods.get() ?? [];

      if (admins.any((x) => x["type"] == "user" && x["id"] == user.id.toString())) {
        return context.respond(MessageBuilder(
          content: "${await userToString(user)} is already an admin.",
        )).toVoid();
      }

      admins.add({"type": "user", "id": user.id.toString()});
      settings.admins.set(admins);

      Modlog.add(ModlogEvent(
        "moduser.add",
        client: context.client,
        guild: context.guild,
        title: "Mod User Added",
        fields: {
          "Who": "<@${user.id}>",
          "Author": "<@${context.user.id}>",
        },
        settings: settings,
      ));

      context.respond(MessageBuilder(
        content: "Added ${await userToString(user)} as a moderator!",
      ));
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("addmodrole", "Add a role as mod.", (T context, Role role) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      final mods = settings.mods.get() ?? [];

      if (mods.any((x) => x["type"] == "role" && x["id"] == role.id.toString())) {
        return context.respond(MessageBuilder(
          content: "Role *${role.name}* is already a moderator.",
        )).toVoid();
      }

      mods.add({"type": "role", "id": role.id.toString()});
      settings.mods.set(mods);

      Modlog.add(ModlogEvent(
        "modrole.add",
        client: context.client,
        guild: context.guild,
        title: "Mod Role Added",
        fields: {
          "Who": "<@${role.id}>",
          "Author": "<@${context.user.id}>",
        },
        settings: settings,
      ));

      context.respond(MessageBuilder(
        content: "Added role *${role.name}* as moderator!",
      ));
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("removemoduser", "Remove a user from mod.", (T context, User user) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final mods = settings.mods.get() ?? [];
      bool found = false;

      mods.removeWhere((x) {
        final y = x["type"] == "user" && x["id"] == user.id.toString();
        if (y) found = true;
        return y;
      });

      if (found) {
        settings.mods.set(mods);

        Modlog.add(ModlogEvent(
          "moduser.remove",
          client: context.client,
          guild: context.guild,
          title: "Mod User Removed",
          fields: {
            "Who": "<@${user.id}>",
            "Author": "<@${context.user.id}>",
          },
          settings: settings,
        ));
      }

      context.respond(MessageBuilder(
        content: found ? "Removed ${await userToString(user)} from mod." : "${await userToString(user)} is not currently an mod.",
      ));
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand.command("removemodrole", "Remove a role from mod.", (T context, Role role) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      final mods = settings.mods.get() ?? [];
      bool found = false;

      mods.removeWhere((x) {
        final y = x["type"] == "role" && x["id"] == role.id.toString();
        if (y) found = true;
        return y;
      });

      if (found) {
        settings.mods.set(mods);

        Modlog.add(ModlogEvent(
          "modrole.remove",
          client: context.client,
          guild: context.guild,
          title: "Mod Role Removed",
          fields: {
            "Who": "<@${role.id}>",
            "Author": "<@${context.user.id}>",
          },
          settings: settings,
        ));
      }

      context.respond(MessageBuilder(
        content: found ? "Removed role *${role.name}* from mod." : "Role *${role.name}* is not currently mod.",
      ));
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),

    BotCommand.command("claim", "Claim yourself as king of the bot!", (T context) async {
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
    BotCommand.command("unclaim", "Step down as king of the bot. This will not be made known to others.", (T context) async {
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
    BotCommand.command("owner", "See stats about who owns the bot, who owns the server, and who's claimed the bot.", (T context) async {
      final settings = context.guild == null ? null : ServerSettings(store, context.guild!.id);
      final mainAdmin = settings?.mainAdmin.get();
      final owners = globalOwners ?? [];
      Map<String, String> results = {};

      for (int i = 0; i < owners.length; i++) {
        final owner = owners[i];
        results["Bot Owner #${i + 1}"] = "**${owner.name}** (*${owner.username}*)";
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
    BotCommand.command("attributes", "See your attributes.", (T context, [@Description('The member to check') User? user]) async {
      final u = user ?? context.user;
      final m = await userToMember(u, guild: context.guild);
      List<String> attributes = ["Alive"];

      final inServer = await () async {
        try {
          if (context.guild == null || context.member == null) return false;
          final _ = await context.guild!.members.get(u.id);
          return true;
        } catch (_) {
          return false;
        }
      }();

      if (inServer) {
        attributes.add("In *${context.guild!.name}*");
        final settings = ServerSettings(store, context.guild!.id);

        if (true /* Was: settings != null */) {
          final mainAdmin = settings.mainAdmin.get();
          final admins = settings.admins.get();
          final mods = settings.mods.get();

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

            for (final a in mods ?? []) {
              if (a["type"] == "user") {
                if (a["id"] == m.id.toString()) {
                  attributes.add("Moderator");
                }
              } else if (a["type"] == "role") {
                for (final x in m.roles) {
                  if (a["id"] == x.id.toString()) {
                    attributes.add("Moderator (role: ${(await x.get()).name})");
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

      if (isOwner(id: u.id, overrideIgnoreOwner: true)) {
        attributes.add(["Owner", if (ignoreOwner) "(ignored)"].join(" "));
      }

      if (context.guild != null) {
        final userSettings = UserPerServerSettings(store, context.guild!.id, u.id);
        final warns = userSettings.warns.get() ?? [];
        if (warns.isNotEmpty) attributes.add("${warns.length} warns (most recent: ${warns.first.timestamp.toDiscordTimestamp(DiscordTimestamp.shortDateTime)})");

        final uSettings = UserPerServerSettings(store, context.guild!.id, u.id);
        if (uSettings.blocked.get()) attributes.add("Blocked from rejoining *${context.guild?.name}*");
      }

      if (context.guild != null) {
        Future<bool> isBanned() async {
          try {
            await context.guild!.manager.fetchBan(context.guild!.id, u.id);
            return true;
          } catch (e) {
            return false;
          }
        }

        Future<DateTime?> getTimeout() async {
          try {
            final member = await context.guild!.members.fetch(u.id);
            bool isTimedOut = member.communicationDisabledUntil != null &&  member.communicationDisabledUntil!.isAfter(DateTime.now());
            return isTimedOut ? member.communicationDisabledUntil : null;
          } catch (e) {
            return null;
          }
        }

        final timeout = await getTimeout();
        if (timeout != null) attributes.add("Timed out until ${timeout.toDiscordTimestamp(DiscordTimestamp.shortDateTime)}");

        final guild = context.guild!;
        if (await isBanned()) attributes.add("Banned from *${guild.name}*");
      }

      try {
        await context.respond(MessageBuilder(
          content: "### Attributes for ${await userOrMemberToString(m, u, client: context.client)}${context.guild != null ? " in *${context.guild!.name}*" : ""}\n\n${attributes.map((x) => "- $x").join("\n")}",
        ));
      } catch (e) {
        Logger.warn("Commands.Status", e);
      }
    }, CommandAttributes(category: "User")),
    BotCommand.command("allsettings", "List all settings for this server. Admin only.", (T context) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = ServerSettings(store, context.guild!.id);
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;
      final all = settings.getAll().entries;

      context.respond(MessageBuilder(
        content: "All settings for *${context.guild?.name}*:\n${all.map((x) => "- `${x.key}`: `${x.value}`").join("\n")}",
      ), level: ResponseLevel.private);
    }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Admin")),
    BotCommand("listadmin", "Admin", "List all admin roles/users.", (T context) async {
      if (await context.assureGuild() == false) return;
      final settings = ServerSettings(store, context.guild!.id);
      final raw = settings.admins.get() ?? [];
      final all = raw.map((x) => (type: x["type"] as String, id: x["id"] as String)).sorted((a, b) => a.id.compareTo(b.id));
      if (all.isEmpty) return context.respondWithError("No admins set.");

      await respondWithPagination(context, PaginatedEmbedBuilder(
        title: "All Admin Roles",
        color: await getColor(context.member),
        pages: EmbedPage.generateFromItems(all.map((x) {
          final id = Snowflake(int.parse(x.id));
          return "- ${x.type.toDiscordCodeString()} ${x.type == "role" ? id.value.toRoleMention() : id.value.toMention()}";
        }).toList()),
      ), settings: settings);
    }),
    BotCommand("warningchannel", "Admin", "Get the text channel used for automatic warnings.", (T context) async {
      if (await context.assureGuild() == false) return;
      final settings = ServerSettings(store, context.guild!.id);
      final id = settings.warningChannel.get();
      if (id == null) return context.respondWithError("No warning channel set.");
      await context.respond(MessageBuilder(content: "Warning channel currently set to ${id.toChannel()}."));
    }),
    BotCommand("setwarningchannel", "Admin", "Get the text channel used for automatic warnings.", (T context, GuildTextChannel channel) async {
      if (await context.assureGuild() == false) return;
      final settings = ServerSettings(store, context.guild!.id);

      try {
        await channel.sendMessage(MessageBuilder(content: "Warning channel set to **this channel**."));
      } catch (e) {
        Logger.warn("WarningChannel", "Unable to send message in channel ${channel.id}: $e");
        return context.respondWithError("Unable to send message in target channel.");
      }

      settings.warningChannel.set(channel.id.value);
      await context.respond(MessageBuilder(content: "Warning channel set to ${channel.toMention()}."));
    }, permissionsRequired: BotCommandPermissions.admin),
    BotCommand("findrole", "Server", "Find a role by ID.", (ChatContext context, int id) async {
      final role = await () async {
        try {
          return context.guild!.roles.get(Snowflake(id));
        } catch (_) {
          return null;
        }
      }();

      await context.respond(MessageBuilder(content: role != null ? "Role `$id`: ${await roleToString(role)}" : "No role found for ID `$id`."));
    }),

    BotCommand("emojis", "Server", "Get all emojis for this server.", (T context) async {
      final emojis = (await context.guild!.emojis.list()).sorted((a, b) => b.createdAt.compareTo(a.createdAt));

      await respondWithPagination(context, PaginatedEmbedBuilder(
        pages: EmbedPage.generate(emojis.map((emoji) {
          return EmbedFieldBuilder(name: emojiToString(emoji) ?? "Emoji ${emoji.id.toDiscordCodeString()}", value: [
            "ID: `${emoji.id}`",
            "Created: ${emoji.createdAt.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} by ${emoji.user?.toMention() ?? "<unknown user>"}",
            /*"Is animated: `${emoji.isAnimated}`",
            "Is available: `${emoji.isAvailable}`",
            "Is managed: `${emoji.isManaged}`",*/
          ].join("\n"), isInline: false);
        }).toList()),
        color: await getColor(context.member),
        footer: ElementBasedEmbedFooterBuilder(elements: ["${emojis.length} Emojis"]),
        title: "All Emojis for ${context.guild?.name}",
      ), settings: ServerSettings(store, context.guild!.id));
    }, needsGuild: true),

    BotCommand("emoji", "Server", "Get all emojis for this server.", (T context, Snowflake id) async {
      final emoji = await tryCatchA(() async => await context.guild!.emojis.fetch(id));
      if (emoji == null) return context.respondWithError("Invalid emoji ID: `$id`");

      await context.respond(MessageBuilder(embeds: [
        EmbedBuilder(
          title: "Emoji Found",
          color: await getColor(context.member),
          description: [
            "# ${emojiToString(emoji) ?? "Emoji ${emoji.id.toDiscordCodeString()}"}",
            "ID: `${emoji.id}`",
            "Created: ${emoji.createdAt.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} by ${emoji.user?.toMention() ?? "<unknown user>"}",
            "Is animated: `${emoji.isAnimated}`",
            "Is available: `${emoji.isAvailable}`",
            "Is managed: `${emoji.isManaged}`",
          ].join("\n"),
          footer: EmbedFooterBuilder(text: "Emoji $id"),
        ),
      ]));
    }, needsGuild: true),
  ];
}