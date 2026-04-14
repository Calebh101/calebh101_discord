import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

class ModerationPlugin extends BotPlugin {
  ModerationPlugin() : super(id: "moderation", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) {
    return [durationConverter()];
  }

  @override
  FutureOr<List<BotCommand>> commands(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("ban", "Moderation", "Ban a user.", (ChatContext context, Member member, [GreedyString? reason]) async {
        try {
          await member.ban(auditLogReason: "${context.user.username}: ${reason?.data ?? "No reason provided"}");
        } on HttpResponseError catch (e) {
          Logger.warn("Ban", "Unable to ban ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Ban ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Banned ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}",
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("timeout", "Moderation", "Time out a user.", (ChatContext context, Member member, Duration duration, [GreedyString? reason]) async {
        try {
          await member.update(MemberUpdateBuilder(communicationDisabledUntil: DateTime.now().add(duration).toUtc()), auditLogReason: "${context.user.username}: ${reason?.data ?? "No reason provided"}");
        } on HttpResponseError catch (e) {
          Logger.warn("Timeout", "Unable to time out ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to time out ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Timed out ${member.toMention()} for ${duration.pretty()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}",
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("timein", "Moderation", "Remove timeout of a user.", (ChatContext context, Member member) async {
        try {
          await member.update(MemberUpdateBuilder(communicationDisabledUntil: null), auditLogReason: context.user.username);
        } on HttpResponseError catch (e) {
          Logger.warn("Timein", "Unable to remove timeout of ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to remove timeout of ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Removed timeout of ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}",
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.admin, aliases: ["untimeout", "remtimeout"]),
    ];
  }
}