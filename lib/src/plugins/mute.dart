import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
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
        final m = await context.respond(MessageBuilder(content: "Updating 0/${channels.length} channels..."));

        for (int i = 0; i < channels.length; i++) {
          final channel = channels[i];
          final ignored = ignore.contains(channel.id);

          if ((i + 1) % 10 == 0) {
            Logger.print("Mute", "Syncing channel $i/${channels.length - 1}. ${channel.id} (${channel.name})... (ignore: $ignored/${ignore.length})");
            await context.updateMessage(m, MessageUpdateBuilder(content: "Updating ${i + 1}/${channels.length} channels..."));
          }

          await channel.updatePermissionOverwrite(PermissionOverwriteBuilder(id: role, type: PermissionOverwriteType.role, deny:
            ((channel.permissionOverwrites.firstWhereOrNull((x) => x.id == role && x.type == PermissionOverwriteType.role)?.deny ?? Permissions(0)) | (ignored ? Permissions(0) : Permissions.addReactions | Permissions.sendMessages | Permissions.sendMessagesInThreads | Permissions.createPublicThreads | Permissions.createPrivateThreads | Permissions.speak | Permissions.requestToSpeak | Permissions.stream | Permissions.useSoundboard)),
          allow: channel.permissionOverwrites.firstWhereOrNull((x) => x.id == role && x.type == PermissionOverwriteType.role)?.allow));
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
        await context.respond(MessageBuilder(content: "Mute role set to ${await roleToString(role)}! Run `syncmute` to sync permissions."));
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
        final results = await mute(member, duration, reason: reason?.data, store: store, guild: context.guild!, author: context.user, client: context.client);

        if (results.result == false) {
          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Mute ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)}\n\nAs a fallback, you can use Discord's timeout.",
              color: await getColor(context.member),
              fields: [
                EmbedFieldBuilder(name: "Reason", value: results.reason ?? "No reason provided", isInline: false),
              ],
              footer: EmbedFooterBuilder(text: "All other mutes for this user have been removed."),
            ),
          ]));
        } else {
          final mute = results.mute!;
          Logger.print("Mute", "Muted ${member.id}: ID=${mute.id}, new=${MuteServerSettings(store, context.guild!.id).mutes.get()?.length}");

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Muted ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)}",
              color: await getColor(context.member),
              fields: [
                EmbedFieldBuilder(name: "Author", value: context.user.toMention(), isInline: false),
                EmbedFieldBuilder(name: "Duration", value: "${mute.time.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} (${mute.time.toDiscordTimestamp(DiscordTimestamp.relative)}) (`${duration.prettyDetailed()}`)", isInline: false),
                EmbedFieldBuilder(name: "ID", value: mute.id.toDiscordCodeBlock(), isInline: false),
              ],
              footer: EmbedFooterBuilder(text: "All other mutes for this user have been removed."),
            ),
          ]));
        }
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin, aliases: ["m"]),
    ];
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      final values = context.store.getAllForKey<List>(Scope.server, "mutes").map((k, v) => MapEntry(Snowflake.parse(k), v.map((x) => Mute.fromJson(x)).toList()));

      for (final entry in values.entries) {
        for (final mute in entry.value) {
          Logger.print("Mute", "Scanning mute ${entry.key}${mute.id} (${mute.user})");

          if (DateTime.now().toUtc().isAfter(mute.time)) {
            Logger.print("Mute", "Auto-unmuting user ${mute.user} (ID=${mute.id})");

            final client = context.clients.clients.values.firstWhereOrNull((x) => x.user.id.value == mute.client);
            if (client == null) continue;
            final guild = await tryCatchA(() async => await client.guilds.get(entry.key));
            final member = await tryCatchA(() async => await guild!.members.get(Snowflake(mute.user)));
            if (guild == null || member == null) continue;

            final settings = MuteServerSettings(context.store, entry.key);
            final mutes = settings.mutes.get() ?? [];
            mutes.removeWhere((x) => x.user == mute.user);
            settings.mutes.set(mutes);

            final muteRole = settings.muteRole.get();
            if (muteRole == null) continue;
            final result = await tryCatchA<bool>(() => member.removeRole(muteRole).to(true)) ?? false;

            if (result == false) {
              Modlog.add(ModlogEvent(
              "mod.unmute",
              title: "Failed to Unmute User",
              fields: {
                "Target": mute.user.toMention(),
                "Reason": "Could not add role `$muteRole`.",
              },
              guild: guild,
              settings: ifGuild(context.store, guild.id, (id) => ServerSettings(context.store, id)),
              client: client,
              severity: ModlogSeverity.severe,
            ));
            }

            Modlog.add(ModlogEvent(
              "mod.unmute",
              title: "Auto-Unmuted User",
              fields: {
                "Target": mute.user.toMention(),
              },
              guild: guild,
              settings: ifGuild(context.store, guild.id, (id) => ServerSettings(context.store, id)),
              client: client,
              severity: ModlogSeverity.good,
            ));
          }
        }
      }
    });

    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        final settings = MuteServerSettings(context.store, event.guildId);
        final mutes = settings.mutes.get() ?? [];
        final mute = mutes.firstWhereOrNull((x) => x.user == event.member.id.value);

        if (mute == null) return;
        final duration = DateTime.now().toUtc().difference(mute.time);
        if (mute.time.difference(DateTime.now().toUtc()) < Duration(seconds: 10)) return;
        await MutePlugin.mute(event.member, duration, reason: "Auto-mute from join", store: context.store, client: client, guild: await event.guild.get());
      });
    });
  }

  static Future<MuteResults> mute(Member member, Duration duration, {required String? reason, required KVStore store, required NyxxGateway client, required Guild guild, User? author}) async {
    final settings = MuteServerSettings(store, guild.id);
    final role = settings.muteRole.get();
    if (role == null) return MuteResults(false, reason: "No mute role set.");

    final mutes = settings.mutes.get() ?? [];
    final until = DateTime.now().toUtc().add(duration);
    final mute = Mute(reason: reason, time: until, id: settings.getNextMuteId(), user: member.id.value, client: client.user.id.value);

    mutes.removeWhere((x) => x.user == member.id.value);
    mutes.add(mute);
    settings.mutes.set(mutes);

    final result = await tryCatchA(() async {
      await member.addRole(role);
      return true;
    }) ?? false;

    if (result == false) {
      return MuteResults(false, reason: "Unable to add role");
    }

    Modlog.add(ModlogEvent(
      "mod.mute",
      title: "Muted User",
      fields: {
        "Target": member.toMention(),
        "Author": author?.toMention() ?? "No author".toDiscordCodeBlock(),
      },
      guild: guild,
      settings: ServerSettings(store, guild.id),
      client: client,
      severity: ModlogSeverity.warning,
    ));

    return MuteResults(result, mute: mute);
  }
}

class MuteResults {
  final bool result;
  final String? reason;
  final Mute? mute;

  const MuteResults(this.result, {this.reason, this.mute});
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
  final int client;

  Mute({required this.reason, required this.time, required this.id, required this.user, required this.client});
  factory Mute.fromJson(Map input) => _$MuteFromJson(input);
  Map toJson() => _$MuteToJson(this);

  @override
  bool operator ==(Object other) {
    return other is Mute && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}