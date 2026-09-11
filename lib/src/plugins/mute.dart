import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'mute.g.dart';

class MutePlugin extends PermOverridePlugin {
  MutePlugin() : super("mute", "Mute");

  @override Flags<Permissions> get allow => Permissions(0);
  @override Flags<Permissions> get deny => Permissions.addReactions | Permissions.sendMessages | Permissions.sendMessagesInThreads | Permissions.createPublicThreads | Permissions.createPrivateThreads | Permissions.speak | Permissions.requestToSpeak | Permissions.stream | Permissions.useSoundboard;

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
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) async {
    return [...(await super.converters(plugin, store)), durationConverter()];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) async {
    return [
      ...(await super.commands(plugin, store)),

      BotCommand("unmute", "Moderation", "Unmute someone.", (T context, Member member) async {
        final settings = MuteServerSettings(store, context.guild!.id);
        final role = settings.pRole.get();
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
      }, needsGuild: true, channelPermissions: Permissions.muteMembers, aliases: ["um"]),
      BotCommand("mute", "Moderation", "Mute someone.", (T context, Member member, [Duration? duration, GreedyString? reason]) async {
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
                EmbedFieldBuilder(name: "Duration", value: mute.time == null || duration == null ? "Forever" : "${mute.time!.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} (${mute.time!.toDiscordTimestamp(DiscordTimestamp.relative)}) (`${duration.prettyDetailed()}`)", isInline: false),
                EmbedFieldBuilder(name: "ID", value: mute.id.toDiscordCodeBlock(), isInline: false),
              ],
              footer: EmbedFooterBuilder(text: "All other mutes for this user have been removed."),
            ),
          ]));
        }
      }, needsGuild: true, channelPermissions: Permissions.muteMembers, aliases: ["m"]),
      BotCommand("mutes", "Moderation", "List all current mutes.", (T context) async {
        final settings = MuteServerSettings(store, context.guildId!);
        final mutes = settings.mutes.get() ?? [];
        if (mutes.isEmpty) return context.respondWithError("No mutes.");

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "Current Mutes for ${context.guild?.name}",
          color: await getColor(context.member),
          footer: ElementBasedEmbedFooterBuilder(elements: ["${mutes.length} Mutes"]),
          pages: EmbedPage.generate(mutes.mapToList((mute) {
            return EmbedFieldBuilder(name: "Mute #${mute.id}", value: "${mute.user.toMention()}\nExpires: ${mute.time?.toDiscordTimestamp(DiscordTimestamp.shortDateTime) ?? "Never"}\nReason: ${mute.reason ?? "No reason provided"}", isInline: false);
          })),
        ), settings: ServerSettings(store, context.guildIdUnsafe));
      }, channelPermissions: Permissions.muteMembers, permissionsRequired: .mod, needsGuild: true),
    ];
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      final values = context.store.getAllForKey<List>(Scope.server, "mutes").map((k, v) => MapEntry(Snowflake.parse(int.tryParse(k) ?? k.split(".")[1]), v.map((x) => Mute.fromJson(x)).toList()));

      for (final entry in values.entries) {
        for (final mute in entry.value) {
          if (mute.time != null && DateTime.now().toUtc().isAfter(mute.time!)) {
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

            final muteRole = settings.pRole.get();
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
        final duration = mute.time == null ? null : DateTime.now().toUtc().difference(mute.time!);
        if (mute.time != null && mute.time!.difference(DateTime.now().toUtc()) < Duration(seconds: 10)) return;
        await MutePlugin.mute(event.member, duration, reason: "Auto-mute from join", store: context.store, client: client, guild: await event.guild.get());
      });
    });
  }

  static Future<MuteResults> mute(Member member, Duration? duration, {required String? reason, required KVStore store, required NyxxGateway client, required Guild guild, User? author}) async {
    final settings = MuteServerSettings(store, guild.id);
    final role = settings.pRole.get();
    if (role == null) return MuteResults(false, reason: "No mute role set.");

    final mutes = settings.mutes.get() ?? [];
    final until = duration == null ? null : DateTime.now().toUtc().add(duration);
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

class MuteServerSettings extends PermOverrideSettings {
  MuteServerSettings(KVStore store, Snowflake id) : super(store, id, "mute");

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
  final DateTime? time;
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