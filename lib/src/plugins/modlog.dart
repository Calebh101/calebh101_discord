import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class ModlogPlugin extends BotPluginLegacy {
  ModlogPlugin() : super(id: "modlog", version: Version.parse("1.0.0A"));

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    Timer.periodic(.new(minutes: 1), (async) async {
      await Modlog.flush();
    });
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand.command(
        "setmodlogchannel", "Set the preferred channel for mod logs. The bot must be able to send a message there.",
        (T context, [GuildTextChannel? channel]) async {
          if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
          final settings = context.guild != null ? ServerSettings(store, context.guild!.id) : null;
          if (settings == null) return context.respondWithError("No settings found.");
          if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

          if (channel == null) {
            settings.modlogChannel.delete();
            await context.respond(MessageBuilder(content: "Modlog channel unset."));
            return;
          }

          try {
            await channel.sendMessage(MessageBuilder(content: "Modlog channel set to **this channel**!"));
          } catch (e) {
            Logger.warn("Commands.ModlogChannel", "Unable to send message in channel ${channel.id}: $e");
            return context.respondWithError("Unable to send message in channel <#${channel.id}>.");
          }

          settings.modlogChannel.set(channel.id.value);
          await context.respond(MessageBuilder(content: "Modlog channel set to <#${channel.id}>!"));
        },
        CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Modlog"),
      ),
      BotCommand("modlogchannel", "Modlog", "Get the current modlog channel.", (T context) async {
        if (await context.assureGuild()) return;
        final settings = ServerSettings(store, context.guild!.id);
        final id = settings.modlogChannel.get();
        await context.respond(MessageBuilder(content: "Modlog channel is currently ${id != null ? "set to ${id.toChannel()}" : "**not set**"}."));
      }),
      BotCommand("modlogpresets", "Modlog", "Get available modlog presets.", (T context) async {
        await context.respond(MessageBuilder(content: ModlogGroup.values.map((group) {
          final scopes = Modlog.getGroup(group);
          return "`${group.name}` (**${scopes.length}**): ${scopes.map((x) => x.toDiscordCodeString()).join(", ")}";
        }).join("\n")));
      }),
      BotCommand("modlogscopes", "Modlog", "Select scopes to log.", (T context, [GreedyString? data]) async {
        final input = data?.data;
        if (Modlog.events.isEmpty) return context.respondWithError("Modlog is not enabled.\n-# No events registered. Did you forget to call `Modlog()`?");

        final settings = context.guild != null ? ServerSettings(store, context.guild!.id) : null;
        if (settings == null) return context.respondWithError("No settings found.");
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

        if (input == null) {
          final current = settings.modlog.get();

          await context.respond(MessageBuilder(
            content: [
              "**${Modlog.events.length}** ${Word.fromCount(Modlog.events.length, singular: Word("scope"))} available: ${Modlog.events.map((x) => "`$x`").join(", ")}",
              if (current?.isNotEmpty ?? false) "**${current!.length}** ${Word.fromCount(current.length, singular: Word("scope"))} enabled: ${current.map((x) => "`$x`").join(", ")}",
            ].join("\n"),
          ));

          return;
        }

        final enabled = <String>[];
        final invalid = <String>[];

        final Set<String> items = input.split(',').map((s) => s.trim()).where((x) => x.isNotEmpty).toSet();

        for (final x in items) {
          final group = ModlogGroup.values.firstWhereOrNull((y) => y.name == x.trim());

          if (group != null) {
            enabled.addAll(Modlog.getGroup(group));
          } else if (Modlog.events.contains(x)) {
            enabled.add(x);
          } else {
            invalid.add(x);
          }
        }

        settings.modlog.set(enabled);

        await context.respond(MessageBuilder(
          content: [
            "**${enabled.length}** ${Word.fromCount(enabled.length, singular: Word("scope"))} enabled: ${enabled.isNotEmpty ? enabled.map((x) => "`$x`").join(", ") : ""}",
            if (invalid.isNotEmpty) "-# **${invalid.length}** ${Word.fromCount(invalid.length, singular: Word("scope"))} are invalid: ${invalid.map((x) => "`$x`").join(", ")}",
            "-# **${Modlog.events.length}** ${Word.fromCount(Modlog.events.length, singular: Word("scope"))} available: ${Modlog.events.map((x) => "`$x`").join(", ")}",
          ].join("\n"),
        ));
      }, permissionsRequired: BotCommandPermissions.admin, aliases: ["setmodlogscopes"], needsGuild: true),
      BotCommand.command("modlogtest", "Send a modlog message.", (T context, String title, String message) async {
        final settings = context.guild != null ? ServerSettings(store, context.guild!.id) : null;
        if (settings == null) return context.respondWithError("No settings found.");
        if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

        final result = await Modlog.add(ModlogEvent("test",
          client: context.client,
          guild: context.guild,
          settings: settings,
          title: title,
          description: message,
          fields: {
            "Author": "<@${context.user.id}>",
          },
          severity: .good,
        ));

        if (result != null) {
          await context.respond(MessageBuilder(
            content: "Modlog message not sent. Reason:\n```$result```",
          ));
        } else {
          await context.respond(MessageBuilder(
            content: "Modlog message sent.",
          ));
        }
      }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Modlog")),
      BotCommand.command("modlogflush", "Flush modlog.", (T context) async {
        final error = await Modlog.flush();
        await context.respond(MessageBuilder(content: error ?? "Success."));
      }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "Modlog")),
      BotCommand("fakemodlog", "Modlog", "Create a fake message deleted modlog.", (T context, User target, Channel channel, DateTime? timestamp, GreedyString content) async {
        timestamp ??= .now().toUtc();
        final random = Random();

        final workerId = random.nextInt(32);
        final processId = random.nextInt(32);
        final increment = random.nextInt(4096);

        final id = Snowflake(
          ((timestamp.millisecondsSinceEpoch - discordEpoch) << 22) |
          (workerId << 17) |
          (processId << 12) |
          increment,
        );

        final result = await Modlog.add(ModlogEvent(
          "message.delete",
          title: "Message Deleted",
          fields: {
            "Author": target.toMention(),
            "ID": id.toDiscordCodeString(),
            "Where": discordLink(context.guildId, channel.id).toString(),
            "Sent": timestamp.toDiscordTimestamp(DiscordTimestamp.shortDateTime),
            "Was": content.toDiscordCodeBlock(language: "md"),
            "Embeds/attachments": "0 embeds, 0 attachments",
          },
          guild: context.guild,
          settings: ifGuild(store, context.guildId, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: .log,
        ));

        await context.respond(MessageBuilder(content: result ?? "Success!\nID: `$id`"));
      }),
    ];
  }
}