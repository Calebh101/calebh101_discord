import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class MemberRolePlugin extends BotPluginLegacy {
  MemberRolePlugin() : super(id: "memberrole", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyRoleList.converter(),
      GreedyMemberList.converter(),
    ];
  }

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [{
      ModlogGroup.all: (levelBelow) => {...levelBelow, "memberroles.set"},
      ModlogGroup.normal: (levelBelow) => {...levelBelow},
      ModlogGroup.quiet: (levelBelow) => {...levelBelow},
      ModlogGroup.off: (_) => {},
    }];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("setmemberroles", "MemberRole", "Set member roles. There can be more than one.", (T context, [GreedyRoleList? roles]) async {
        final settings = MemberRoleSettings(store, context.guild!.id);

        if (roles == null || roles.input.isEmpty) {
          settings.memberRoles.delete();
          await context.respond(MessageBuilder(content: "Member roles disabled."));
          return;
        }

        final all = roles.input;
        settings.memberRoles.set(all.map((x) => x.id).toList());
        await context.respond(MessageBuilder(content: "Member roles updated.\n\n${(await Future.wait(all.map((x) async => "- ${await roleToString(x)}"))).join("\n")}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true, aliases: ["setmemberrole"]),
      BotCommand("memberroles", "MemberRole", "Get member roles.", (T context) async {
        final settings = MemberRoleSettings(store, context.guild!.id);
        final roles = settings.memberRoles.get() ?? [];

        if (roles.isEmpty) {
          settings.memberRoles.delete();
          await context.respond(MessageBuilder(content: "No member roles set."));
          return;
        }

        await context.respond(MessageBuilder(content: (await Future.wait(roles.map((x) async {
          return "- ${await roleToString(await tryCatchA<Role?>(() => getRole(context.guild!, x))) ?? "Invalid role: `$x`"}";
        }))).join("\n")));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true, aliases: ["memberroles"]),
      BotCommand("mrignore", "MemberRole", "Ignore someone (or a list of people) from the member roles.", (T context, GreedyMemberList members) async {
        final settings = MemberRoleSettings(store, context.guild!.id);
        final current = settings.memberRolesIgnored.get() ?? [];

        current.addAll(members.input.map((x) => x.id));
        settings.memberRolesIgnored.set(current);

        await context.respond(MessageBuilder(content: "Ignored **${members.input.length}** people."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("mrunignore", "MemberRole", "Unignore someone (or a list of people) from the member roles.", (T context, GreedyMemberList members) async {
        final settings = MemberRoleSettings(store, context.guild!.id);
        final current = settings.memberRolesIgnored.get() ?? [];
        final valid = members.input.where((x) => current.any((y) => x.id == y));

        current.removeWhere((x) => valid.any((y) => x == y.id));
        settings.memberRolesIgnored.set(current);

        await context.respond(MessageBuilder(content: "Unignored **${valid.length}/${members.input.length}** people."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("mrignored", "MemberRole", "Get if someone (or a list of people) is ignored from the member roles.", (T context, Member member) async {
        final settings = MemberRoleSettings(store, context.guild!.id);
        final current = settings.memberRolesIgnored.get() ?? [];
        final ignored = current.any((x) => x == member.id);

        await context.respond(MessageBuilder(content: "${await memberToString(member, client: context.client)} ${ignored ? "**is currently**" : "is **not**"} ignored."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("mreval", "MemberRole", "Evaluate member roles.", (T context, [Member? member]) async {
        final settings = MemberRoleSettings(store, context.guild!.id);
        final ids = settings.memberRoles.get() ?? [];
        final ignored = settings.memberRolesIgnored.get() ?? [];
        final count = (await context.guild!.fetch(withCounts: true)).approximateMemberCount!;

        if (member == null && count > 1000) {
          final result = await confirmation("evaluate $count members (this can take a while)", context);
          if (result.result != true) return;
        }

        final members = member != null ? [member] : (await getAllMembers(context.guild!)).where((x) => !isIgnored(store, x.id) && !ignored.contains(x.id));
        final m = await context.respond(MessageBuilder(content: "Evaluating **${members.length}** members...\n-# This might take a while."));

        Logger.print("MemberRole", "Evaluating ${ids.length} role IDs and ${members.length} members");
        final List<Role> roles = [];

        for (final id in ids) {
          try {
            roles.add(await context.guild!.roles.get(id));
          } catch (e) {
            Logger.warn("MemberRole", "Invalid role ${context.guild?.id}.$id: $e");
          }
        }

        await Future.wait(members.map((member) async {
          await Future.wait(roles.map((role) async {
            try {
              await member.addRole(role.id);
            } catch (e) {
              Logger.warn("MemberRole", "Unable to add role ${context.guild?.id}.${role.id}: $e");
            }
          }));
        }));

        await context.updateMessage(m, MessageUpdateBuilder(content: "Evaluated **${members.length}** members and **${roles.length}** valid roles."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
    ];
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        if (isIgnored(store, event.member.id)) return;
        final settings = MemberRoleSettings(store, event.guildId);
        final ignored = settings.memberRolesIgnored.get() ?? [];
        if (ignored.contains(event.member.id)) return;

        final roles = settings.memberRoles.get() ?? [];
        final guild = await event.guild.get();

        List<Role> success = [];
        List<Snowflake> fail = [];

        await Future.wait(roles.map((id) async {
          try {
            final role = await guild.roles.get(id);
            await event.member.addRole(role.id);
            success.add(role);
          } catch (e) {
            Logger.warn("MemberRole", "Unable to add role ${guild.id}.$id: $e");
            fail.add(id);
          }
        }));

        Modlog.add(ModlogEvent(
          "memberroles.set",
          client: client,
          guild: guild,
          settings: settings,
          title: "${roles.length} Member Roles Set",
          fields: {
            "Target": event.member.toMention(),
            "Success (${success.length})": (await Future.wait(success.map((x) async => "- ${await roleToString(x)}"))).join("\n"),
            "Fail (${fail.length})": fail.map((x) => "- `$x`").join(", "),
          },
          severity: fail.isEmpty ? .good : .warning,
        ));
      });
    });
  }
}

class MemberRoleSettings extends Calebh101BotServerSettings {
  MemberRoleSettings(super.store, super.id);

  SettingsObject<List<Snowflake>> get memberRoles => SettingsObject.listSnowflake(this, "memberRoles");
  SettingsObject<List<Snowflake>> get memberRolesIgnored => SettingsObject.listSnowflake(this, "memberRolesIgnored");
}