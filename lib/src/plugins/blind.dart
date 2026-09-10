import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'blind.g.dart';

class BlindPlugin extends PermOverridePlugin {
  BlindPlugin() : super("blind", "Blind");

  @override Flags<Permissions> get allow => Permissions(0);
  @override Flags<Permissions> get deny => Permissions.viewChannel;

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [{
      ModlogGroup.all: (levelBelow) => {...levelBelow},
      ModlogGroup.normal: (levelBelow) => {...levelBelow, "mod.blind", "mod.unblind"},
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

      BotCommand("unblind", "Moderation", "Unblind someone.", (T context, Member member) async {
        final settings = BlindServerSettings(store, context.guild!.id);
        final role = settings.pRole.get();
        if (role == null) return context.respondWithError("No blind role set.");

        final blinds = settings.blinds.get() ?? [];
        blinds.removeWhere((x) => x.user == member.id.value);
        settings.blinds.set(blinds);

        final result = await tryCatchA(() async {
          await member.removeRole(role);
          return true;
        }) ?? false;

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## ${result ? "Unblinded" : "Unable to Unblind"} ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)})",
            color: await getColor(context.member),
          ),
        ]));

        Modlog.add(ModlogEvent(
          "mod.unblind",
          title: "unblinded User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("blind", "Moderation", "Blind someone.", (T context, Member member, [Duration? duration, GreedyString? reason]) async {
        final results = await blind(member, duration, reason: reason?.data, store: store, guild: context.guild!, author: context.user, client: context.client);

        if (results.result == false) {
          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Blind ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)}\n\nAs a fallback, you can use Discord's timeout.",
              color: await getColor(context.member),
              fields: [
                EmbedFieldBuilder(name: "Reason", value: results.reason ?? "No reason provided", isInline: false),
              ],
              footer: EmbedFooterBuilder(text: "All other blinds for this user have been removed."),
            ),
          ]));
        } else {
          final blind = results.blind!;
          Logger.print("Blind", "Blinded ${member.id}: ID=${blind.id}, new=${BlindServerSettings(store, context.guild!.id).blinds.get()?.length}");

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Blinded ${member.toMention()} (${await memberToString(member, client: context.client, detailed: true)}",
              color: await getColor(context.member),
              fields: [
                EmbedFieldBuilder(name: "Author", value: context.user.toMention(), isInline: false),
                EmbedFieldBuilder(name: "Duration", value: blind.time == null || duration == null ? "Forever" : "${blind.time!.toDiscordTimestamp(DiscordTimestamp.shortDateTime)} (${blind.time!.toDiscordTimestamp(DiscordTimestamp.relative)}) (`${duration.prettyDetailed()}`)", isInline: false),
                EmbedFieldBuilder(name: "ID", value: blind.id.toDiscordCodeBlock(), isInline: false),
              ],
              footer: EmbedFooterBuilder(text: "All other blinds for this user have been removed."),
            ),
          ]));
        }
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("blinds", "Moderation", "List all current blinds.", (T context) async {
        final settings = BlindServerSettings(store, context.guildId!);
        final blinds = settings.blinds.get() ?? [];
        if (blinds.isEmpty) return context.respondWithError("No blinds.");

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "Current Blinds for ${context.guild?.name}",
          color: await getColor(context.member),
          footer: ElementBasedEmbedFooterBuilder(elements: ["${blinds.length} Blinds"]),
          pages: EmbedPage.generate(blinds.mapToList((blind) {
            return EmbedFieldBuilder(name: "Blind #${blind.id}", value: "${blind.user.toMention()}\nExpires: ${blind.time?.toDiscordTimestamp(DiscordTimestamp.shortDateTime) ?? "Never"}\nReason: ${blind.reason ?? "No reason provided"}", isInline: false);
          })),
        ), settings: ServerSettings(store, context.guildIdUnsafe));
      }, permissionsRequired: .mod, needsGuild: true),
    ];
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      final values = context.store.getAllForKey<List>(Scope.server, "blinds").map((k, v) => MapEntry(Snowflake.parse(int.tryParse(k) ?? k.split(".")[1]), v.map((x) => Blind.fromJson(x)).toList()));

      for (final entry in values.entries) {
        for (final blind in entry.value) {
          if (blind.time != null && DateTime.now().toUtc().isAfter(blind.time!)) {
            Logger.print("Blind", "Auto-unmuting user ${blind.user} (ID=${blind.id})");

            final client = context.clients.clients.values.firstWhereOrNull((x) => x.user.id.value == blind.client);
            if (client == null) continue;
            final guild = await tryCatchA(() async => await client.guilds.get(entry.key));
            final member = await tryCatchA(() async => await guild!.members.get(Snowflake(blind.user)));
            if (guild == null || member == null) continue;

            final settings = BlindServerSettings(context.store, entry.key);
            final blinds = settings.blinds.get() ?? [];
            blinds.removeWhere((x) => x.user == blind.user);
            settings.blinds.set(blinds);

            final blindRole = settings.pRole.get();
            if (blindRole == null) continue;
            final result = await tryCatchA<bool>(() => member.removeRole(blindRole).to(true)) ?? false;

            if (result == false) {
              Modlog.add(ModlogEvent(
              "mod.unblind",
              title: "Failed to Unblind User",
              fields: {
                "Target": blind.user.toMention(),
                "Reason": "Could not add role `$blindRole`.",
              },
              guild: guild,
              settings: ifGuild(context.store, guild.id, (id) => ServerSettings(context.store, id)),
              client: client,
              severity: ModlogSeverity.severe,
            ));
            }

            Modlog.add(ModlogEvent(
              "mod.unblind",
              title: "Auto-unblinded User",
              fields: {
                "Target": blind.user.toMention(),
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
        final settings = BlindServerSettings(context.store, event.guildId);
        final blinds = settings.blinds.get() ?? [];
        final blind = blinds.firstWhereOrNull((x) => x.user == event.member.id.value);

        if (blind == null) return;
        final duration = blind.time == null ? null : DateTime.now().toUtc().difference(blind.time!);
        if (blind.time != null && blind.time!.difference(DateTime.now().toUtc()) < Duration(seconds: 10)) return;
        await BlindPlugin.blind(event.member, duration, reason: "Auto-blind from join", store: context.store, client: client, guild: await event.guild.get());
      });
    });
  }

  static Future<BlindResults> blind(Member member, Duration? duration, {required String? reason, required KVStore store, required NyxxGateway client, required Guild guild, User? author}) async {
    final settings = BlindServerSettings(store, guild.id);
    final role = settings.pRole.get();
    if (role == null) return BlindResults(false, reason: "No blind role set.");

    final blinds = settings.blinds.get() ?? [];
    final until = duration == null ? null : DateTime.now().toUtc().add(duration);
    final blind = Blind(reason: reason, time: until, id: settings.getNextBlindId(), user: member.id.value, client: client.user.id.value);

    blinds.removeWhere((x) => x.user == member.id.value);
    blinds.add(blind);
    settings.blinds.set(blinds);

    final result = await tryCatchA(() async {
      await member.addRole(role);
      return true;
    }) ?? false;

    if (result == false) {
      return BlindResults(false, reason: "Unable to add role");
    }

    Modlog.add(ModlogEvent(
      "mod.blind",
      title: "Blinded User",
      fields: {
        "Target": member.toMention(),
        "Author": author?.toMention() ?? "No author".toDiscordCodeBlock(),
      },
      guild: guild,
      settings: ServerSettings(store, guild.id),
      client: client,
      severity: ModlogSeverity.warning,
    ));

    return BlindResults(result, blind: blind);
  }
}

class BlindResults {
  final bool result;
  final String? reason;
  final Blind? blind;

  const BlindResults(this.result, {this.reason, this.blind});
}

class BlindServerSettings extends PermOverrideSettings {
  BlindServerSettings(KVStore store, Snowflake id) : super(store, id, "blind");

  SettingsObject<List<Blind>> get blinds => SettingsObject(this, "blinds", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Blind.fromJson(x)).toList());
  SettingsObject<int> get blindId => SettingsObject(this, "blindId");

  int getNextBlindId() {
    final current = blindId.get() ?? 0;
    final next = current + 1;
    blindId.set(next);
    return next;
  }
}

@JsonSerializable(anyMap: true)
class Blind {
  final String? reason;
  final DateTime? time;
  final int id;
  final int user;
  final int client;

  Blind({required this.reason, required this.time, required this.id, required this.user, required this.client});
  factory Blind.fromJson(Map input) => _$BlindFromJson(input);
  Map toJson() => _$BlindToJson(this);

  @override
  bool operator ==(Object other) {
    return other is Blind && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}