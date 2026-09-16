import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class RolesPlugin extends BotPlugin {
  @override
  BotPluginInfo get info => .new(id: "roles", description: "Provides utilities for roles.", version: Version.parse("1.0.0A"));

  static const prefix = "roleselector-";
  static const watermark = "Role Selector";

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      RoleSelectorDataStore.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("addrole", "Moderation", "Add a role to someone. This is non-sticky.", (ChatContext context, Member member, Role role) async {
        if (await context.assureGuild() == false) return;

        try {
          await member.addRole(role.id);
        } catch (e) {
          Logger.warn("StickyRoles", "Unable to add role ${role.id}: $e");
          return context.respondWithError("We couldn't add role ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}.");
        }

        await context.respond(MessageBuilder(content: "Added role ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}!"));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["r+"]),
      BotCommand("addsrole", "Moderation", "Add a sticky role to someone.", (ChatContext context, Member member, Role role) async {
        if (await context.assureGuild() == false) return;
        final settings = StickyRolesSettings(store, context.guild!.id, member.id);

        try {
          await member.addRole(role.id);
        } catch (e) {
          Logger.warn("StickyRoles", "Unable to add role ${role.id}: $e");
          return context.respondWithError("We couldn't add role ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}.");
        }

        final current = settings.stickyRoles.get() ?? [];
        current.add(role.id.value);
        settings.stickyRoles.set(current);

        await context.respond(MessageBuilder(content: "Added sticky role ${await roleToString(role)} to user ${await memberToString(member, client: context.client)}!"));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["sr+", "rs+", "addroles"]),
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
      BotCommand("stickyroles", "Roles", "List someone's current sticky roles.", (ChatContext context, Member member) async {
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
      }, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("clearstickyroles", "Roles", "Clear someone's current sticky roles.", (ChatContext context, Member member) async {
        if (await context.assureGuild() == false) return;
        final settings = StickyRolesSettings(store, context.guild!.id, member.id);
        final current = settings.stickyRoles.get() ?? [];

        settings.stickyRoles.delete();
        await context.respond(MessageBuilder(content: "Removed **${current.length}** sticky role entries from ${await memberToString(member, client: context.client)}.\nTheir existing roles were not affected."));
      }, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("allstickyroles", "Roles", "List everyone's current sticky roles.", (ChatContext context) async {
        if (await context.assureGuild() == false) return;
        final ids = Map.fromEntries(store.getAllForKey<List<dynamic>>(.userPerServer, "sr").entries.where((x) => UserPerServerSettings.parseId(x.key).server == context.guildId)).map((k, v) => MapEntry(Snowflake.parse(UserPerServerSettings.parseId(k).user), v.map((x) => Snowflake(x)).toList()));

        await context.respond(MessageBuilder(content: "Current sticky roles for **${ids.length}** users:\n\n${(await Future.wait(ids.mapTo((k, v) async {
          return "- ${k.value.toMention()}: ${v.map((x) => x.value.toRoleMention()).join(" ")}";
        }))).join("\n")}", allowedMentions: AllowedMentions(repliedUser: true)));
      }, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("evalstickyroles", "Roles", "Evaluate someone's sticky roles.", (ChatContext context, Member member) async {
        if (await context.assureGuild() == false) return;
        final results = await eval(store: store, guild: context.guild!, member: member, client: context.client, author: context.user);
        await context.respond(MessageBuilder(content: "Current sticky roles for user ${await memberToString(member, client: context.client)}:\n\n${results.join("\n")}"));
      }, permissionsRequired: BotCommandPermissions.admin),

      BotCommand("roleselector", "Roles", "Role selector!", (T context, String title, String? description, RoleSelectorDataStore roles) async {
        final List<ButtonBuilder> buttons = roles.data.mapToList((data) {
          final role = data.role;

          return .new(
            style: data.style ?? .primary,
            customId: "$prefix${role.id}",
            label: data.name ?? role.name,
          );
        });

        final List<ActionRowBuilder> rows = [];

        for (int i = 0; i < buttons.length; i += 5) {
          final end = i + 5 > buttons.length ? buttons.length : i + 5;
          final chunk = buttons.sublist(i, end);
          rows.add(.new(components: chunk));
        }

        for (int i = 0; i < rows.length; i += 5) {
          final end = i + 5 > rows.length ? rows.length : i + 5;
          final chunk = rows.sublist(i, end);

          await context.channel.sendMessage(.new(
            components: chunk,
            embeds: i == 0 ? [
              .new(
                title: title,
                description: description ?? "Select any of the **${roles.data.length}** roles below.\nYou can freely add/remove them.",
                color: await getColor(context.member),
                footer: .new(text: watermark),
              ),
            ] : null,
          ));
        }
      }, needsGuild: true, permissionsRequired: .admin, triggerTyping: false, extendedDescription: """
How the data works:
Each item is a key-value thing wrapped in parenthesis.
Example:

```
(role: <@1546275279561826354>, name: Dogs)
```

There are 3 keys:
- `role`: Required. You can put a name, ID, or mention here.
- `name`: Not required. Defaults to the name of the role.
- `style`: Button style. See below for possible values here.

Make sure to not use quotes around keys!
You can use **double** quotes around values.


When using the items here, just split each one with spaces.
Example:

```
!roleselector (role: <@1546275279561826354>, name: Dogs 🐶) (role: <@1546275446046331000>, name: Cats 🐱, style: secondary)
```


Possible button styles:\n${buttonStyles.entries.sorted((a, b) {
  return a.value.value.compareTo(b.value.value);
}).map((entry) {
  return "- `${entry.key}` (`${entry.value.value}`)";
}).join("\n")}
""".trim()),
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
      severity: .log,
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

  Future<String?> handleRoleEvent(InteractionCreateEvent<Interaction> event) async {
    final interaction = event.interaction;
    if (interaction is! MessageComponentInteraction) return "Invalid type: ${interaction.runtimeType}";

    final member = interaction.member;
    if (member == null) return "No member";

    final guild = await interaction.guild?.get();
    if (guild == null) return "No guild";

    final data = interaction.data;
    final customId = data.customId;

    if (!customId.startsWith(prefix)) return "Invalid custom ID: $customId (expected starting with $prefix)";
    await interaction.acknowledge(isEphemeral: true);

    final id = Snowflake.parse(customId.replaceFirst(prefix, ""));
    final has = member.roleIds.contains(id);

    if (has) {
      await member.removeRole(id, auditLogReason: "Requested from role selector");
    } else {
      await member.addRole(id, auditLogReason: "Requested from role selector");
    }

    await interaction.respond(MessageBuilder(
      content: "${has ? "Removed" : "Added"} role ${id.toRoleMention()}.",
      flags: MessageFlags.ephemeral,
      allowedMentions: .new(repliedUser: true),
    ));

    return "Handled: ${has ? "removed" : "added"}";
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        await eval(store: context.store, guild: await event.guild.get(), member: event.member, client: client);
      });

      client.onInteractionCreate.listen((event) async {
        try {
          final result = await handleRoleEvent(event);
          if (dev) Logger.print("Roles", "Interaction ${event.interaction.id}: $result");
        } catch (e, s) {
          Logger.warn("Roles", "Interaction ${event.interaction.id}: $e\n$s");
        }
      });
    });
  }
}

const Map<String, ButtonStyle> buttonStyles = {
  "danger": .danger,
  "link": .link,
  "premium": .premium,
  "primary": .primary,
  "secondary": .secondary,
  "success": .success,
};

class StickyRolesSettings extends UserPerServerSettings {
  StickyRolesSettings(super.store, super.server, super.user);

  SettingsObject<List<int>> get stickyRoles => SettingsObject.list<int>(this, "sr");
}

final class RoleSelectorData(final Role role, final String? name, final ButtonStyle? style);

extension type RoleSelectorDataStore(List<RoleSelectorData> data) {
  static Null log(String input) {
    if (dev) Logger.print("RoleSelector", "Converting: $input");
    return null;
  }

  static Null error(ContextData context, String input) {
    if (dev) Logger.warn("RoleSelector", "Converting: $input");
    tryCatchA(() async => await context.channel.sendMessage(.new(content: "Error: $input")));
    return null;
  }

  static BotConverter<RoleSelectorDataStore> converter() {
    return BotConverter("RoleSelectorData", (_) => Converter<RoleSelectorDataStore>((value, context) async {
      final List<RoleSelectorData> data = [];
      value.skipWhitespace();
      log("Going off of value of ${value.remaining.length} characters");

      while (!value.eof) {
        if (value.current != "(") return error(context, "Didn't find (");
        value.index++;
        String object = "";

        while (value.current != ")" && !value.eof) {
          object += value.current;
          value.index++;
        }

        if (value.eof) return error(context, "Premature eof");
        value.index++;

        final items = object.split(",");
        final Map<String, dynamic> kv = {};

        for (final item in items) {
          final idx = item.indexOf(":");
          if (idx == -1) return error(context, "No value for key ${item.trim()}");

          var key = item.substring(0, idx).toLowerCase().trim();
          var raw = item.substring(idx + 1).trim();

          if (key.length >= 2 && key.startsWith('"') && key.endsWith('"')) key = key.substring(1, key.length - 1);
          if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) raw = raw.substring(1, raw.length - 1);

          final value = await switch (key) {
            "role" => roleConverter.convert(.new(raw), context),
            "name" => raw,
            "style" => buttonStyles.entries.firstWhereOrNull((x) => x.key == raw.toLowerCase().trim() || x.value.value == .tryParse(raw.trim()))?.value,
            _ => null,
          };

          if (value == null) return error(context, "Value was null for key $key");
          kv[key] = value;
        }

        log("Found keys: ${kv.mapTo((k, v) => "($k: ${v.runtimeType})").join(", ")}");
        final role = kv["role"];
        if (role is! Role) return null;

        data.add(.new(role, kv["name"], kv["style"]));
        value.skipWhitespace();
      }

      log("Produced ${data.length} items");
      return .new(data);
    }));
  }
}