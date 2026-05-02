import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:json_annotation/json_annotation.dart';

part 'mute.g.dart';

class MutePlugin extends BotPlugin {
  MutePlugin() : super(id: "mute", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [{
      ModlogGroup.all: (levelBelow) => {...levelBelow},
      ModlogGroup.normal: (levelBelow) => {...levelBelow, "mod.mute", "mod.unmute"},
      ModlogGroup.quiet: (levelBelow) => {...levelBelow},
      ModlogGroup.off: (_) => {},
    }];
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [GreedyGuildTextChannelList.converter(), durationConverter()];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("syncmute", "Mute", "Sync the mute role.", (T context) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final role = settings.muteRole.get();
        final ignore = settings.muteIgnoreChannels.get() ?? [];

        if (role == null) {
          return context.respondWithError("No mute role set.");
        }

        final channels = await context.guild!.fetchChannels();
        final m = await context.respond(MessageBuilder(content: "Updating ${channels.length} channels..."));

        for (int i = 0; i < channels.length; i++) {
          final channel = channels[i];
          final ignored = ignore.contains(channel.id);
          Logger.print("Mute", "Syncing channel $i/${channels.length - 1} ${channel.id} (${channel.name})... (ignore: $ignored/${ignore.length})");

          await channel.updatePermissionOverwrite(PermissionOverwriteBuilder(id: role, type: PermissionOverwriteType.role, deny: ignored ? null :
            Permissions.addReactions | Permissions.sendMessages | Permissions.sendMessagesInThreads | Permissions.createPublicThreads | Permissions.createPrivateThreads | Permissions.speak | Permissions.requestToSpeak | Permissions.stream | Permissions.useSoundboard,
          ));
        }

        await context.updateMessage(m, MessageUpdateBuilder(content: "Updated ${channels.length} channels!"));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setmuterole", "Mute", "Set the mute role.", (T context, [Role? role]) async {
        final settings = MuteServerSettings(store, context.guild!.id);

        if (role == null) {
          settings.muteRole.delete();
          await context.respond(MessageBuilder(content: "Mute role deleted."));
          return;
        }

        settings.muteRole.set(role.id);
        await context.respond(MessageBuilder(content: "Mute role set to ${await roleToString(role)}!"));
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("setmuteignored", "Mute", "Set channels that are ignored from syncing the mute role.", (T context, [GreedyGuildTextChannelList? channels]) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        settings.muteIgnoreChannels.set(channels?.input.map((x) => x.id).toList());
        await context.respond(MessageBuilder(content: "Now ignoring **${channels?.input.length ?? 0}** channels."));
      }, needsGuild: true, permissionsRequired: .admin),
      BotCommand("muterole", "Mute", "Get the current mute role.", (T context) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final id = settings.muteRole.get();
        final role = await tryCatchA(() => context.guild!.roles.get(id!));
        await context.respond(MessageBuilder(content: role != null ? "Current mute role: ${await roleToString(role)}" : (id != null ? "Invalid role set: ${id.toDiscordCodeString()}" : "No mute role set.")));
      }, needsGuild: true),
      BotCommand("muteignored", "Mute", "Get the current mute role ignored channels.", (T context) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final channels = settings.muteIgnoreChannels.get() ?? [];

        await context.respond(MessageBuilder(content: channels.isEmpty ? "No channels ignored." : "**${channels.length}** ignored mute channels:\n\n${channels.map((x) {
          return "- ${x.value.toChannel()} (`$x`)";
        })}"));
      }, needsGuild: true),
      BotCommand("unmute", "Mute", "Get the current mute role ignored channels..", (T context, Member member) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final role = settings.muteRole.get();
        if (role == null) return context.respondWithError("No mute role set.");

        final mutes = settings.mutes.get() ?? [];
        mutes.removeWhere((x) => x.user == member.id.value);
        settings.mutes.set(mutes);

        final result = await tryCatchA(() async {
          await member.removeRole(role);
          return true;
        }) ?? false;

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## ${result ? "Unmuted" : "Unable to Unmute"} ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)})",
            color: await getColor(context.member),
          ),
        ]));

        Modlog.add(ModlogEvent(
          "mod.unmute",
          title: "Unmuted User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin, aliases: ["um"]),
      BotCommand("mute", "Mute", "Get the current mute role ignored channels..", (T context, Member member, Duration duration, [GreedyString? reason]) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final role = settings.muteRole.get();
        if (role == null) return context.respondWithError("No mute role set.");

        final mutes = settings.mutes.get() ?? [];
        final mute = Mute(reason: reason?.data, time: DateTime.now().toUtc().add(duration), id: settings.getNextMuteId(), user: member.id.value);
        mutes.add(mute);
        settings.mutes.set(mutes);

        final result = await tryCatchA(() async {
          await member.addRole(role);
          return true;
        }) ?? false;

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## ${result ? "Muted" : "Unable to Mute"} ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)})",
            color: await getColor(context.member),
            fields: [
              EmbedFieldBuilder(name: "ID", value: mute.id.toDiscordCodeBlock(), isInline: false),
            ],
          ),
        ]));

        Modlog.add(ModlogEvent(
          "mod.mute",
          title: "Muted User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.warning,
        ));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin, aliases: ["m"]),
    ];
  }
}

class MuteServerSettings extends ServerSettings {
  MuteServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get muteRole => SettingsObject.snowflake(this, "muteRole");
  SettingsObject<List<Snowflake>> get muteIgnoreChannels => SettingsObject.listSnowflake(this, "muteIgnore");
  SettingsObject<List<Mute>> get mutes => SettingsObject(this, "mutes", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Mute.fromJson(x)).toList());
  SettingsObject<int> get muteId => SettingsObject(this, "muteId");

  int getNextMuteId() {
    final current = muteId.get() ?? 0;
    final next = current + 1;
    muteId.set(next);
    return next;
  }
}

@JsonSerializable(anyMap: true)
class Mute {
  final String? reason;
  final DateTime time;
  final int id;
  final int user;

  Mute({required this.reason, required this.time, required this.id, required this.user});
  factory Mute.fromJson(Map input) => _$MuteFromJson(input);
  Map toJson() => _$MuteToJson(this);

  @override
  bool operator ==(Object other) {
    return other is Mute && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}