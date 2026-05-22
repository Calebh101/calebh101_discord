import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:chrono_dart/chrono_dart.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'moderation.g.dart';

class ModerationPlugin extends BotPluginLegacy {
  ModerationPlugin() : super(id: "moderation", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotConverter>> converters(CommandsPlugin plugin, KVStore store) {
    return [durationConverter(), Or.converter<Member, Snowflake>(), GreedyRoleList.converter(), GreedyGuildTextChannelList.converter()];
  }

  Future<String> confirmstringify(Member member, NyxxGateway client) async {
    final user = member.user ?? await client.users[member.id].get();

    try {
      return [
        (member.nick ?? user.globalName ?? user.username),
        "(${user.username})",
        "(${member.id})",
      ].join(" ");
    } catch (e) {
      Logger.print("confirmstringify", "$e (member=${member.runtimeType}, user=${member.user.runtimeType}, nick=${member.nick}, id=${member.id}");
      return await userToString(user, detailed: true) ?? "undefined";
    }
  }

  Future<String> confirmstringifyorid(Snowflake? id, Member? member, NyxxGateway client) async {
    if (member != null) {
      final user = member.user ?? await client.users[member.id].get();

      try {
        return [
          (member.nick ?? user.globalName ?? user.username),
          "(${user.username})",
          "(${member.id})",
        ].join(" ");
      } catch (e) {
        Logger.print("confirmstringify", "$e (member=${member.runtimeType}, user=${member.user.runtimeType}, nick=${member.nick}, id=${member.id}");
        return await userToString(user, detailed: true) ?? "undefined";
      }
    } else if (id != null) {
      return id.toString();
    } else {
      return "*No data*";
    }
  }

  Future<bool> confirm(ChatContext context, String action, {bool deleteUserConfirmationInput = false}) async {
    final result = await confirmation(action, context, deleteUserConfirmationInput: deleteUserConfirmationInput);
    if (result.result == true) return true;
    await context.respond(MessageBuilder(embeds: [result.toEmbed()]));
    return false;
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("block", "Moderation", "Block a user. Next time they joined this guild, they will get instantly banned.", (T context, Snowflake userId, [GreedyString? reason]) async {
        final settings = UserPerServerSettings(store, context.guild!.id, userId);
        if (settings.blocked.get() == true) return context.respondWithError("User is already blocked.");
        if (await confirm(context, "block $userId") == false) return;
        settings.blocked.set(true);

        Modlog.add(ModlogEvent(
          "mod.block.set",
          title: "Blocked User",
          fields: {
            "Target": userId.value.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.severe,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Blocked ${userId.value.toMention()} (`$userId`)",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, userId, guild: context.guild!),
              EmbedFieldBuilder(name: "Reason", value: reason?.data ?? "No reason provided.", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, needsGuild: true),
      BotCommand("unblock", "Moderation", "Unblock a user.", (T context, Snowflake userId) async {
        final settings = UserPerServerSettings(store, context.guild!.id, userId);
        if (settings.blocked.get() == false) return context.respondWithError("User is already unblocked.");
        if (await confirm(context, "unblock $userId") == false) return;
        settings.blocked.set(true);

        Modlog.add(ModlogEvent(
          "mod.block.set",
          title: "Unblocked User",
          fields: {
            "Target": userId.value.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Unblocked ${userId.value.toMention()} (`$userId`)",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, userId, guild: context.guild!),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, needsGuild: true),
      BotCommand("ban", "Moderation", "Ban a user.", (T context, Or<Member, Snowflake> input, [GreedyString? reason]) async {
        final id = input.$1?.id ?? input.$2!;

        try {
          if (await confirm(context, "ban ${await confirmstringifyorid(id, input.$1, context.client)}") == false) return;
          final settings = ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id));
          var deleteMessagesSeconds = settings?.banMessageRemovalSeconds.get();
          if (deleteMessagesSeconds == null || deleteMessagesSeconds <= 0) deleteMessagesSeconds = null;
          await context.guild!.createBan(id, auditLogReason: "${context.user.username}: ${reason?.data ?? "No reason provided"}", deleteMessages: deleteMessagesSeconds != null ? Duration(seconds: deleteMessagesSeconds) : null);
        } on HttpResponseError catch (e) {
          Logger.warn("Ban", "Unable to ban $id: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Ban ${id.value.toMention()}\n${await memberToString(input.$1, client: context.client, detailed: true) ?? id}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        Modlog.add(ModlogEvent(
          "mod.ban",
          title: "Banned User",
          fields: {
            "Target": id.value.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.severe,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Banned ${id.value.toMention()}\n${await memberToString(input.$1, client: context.client, detailed: true) ?? id.toDiscordCodeString()}",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, id, guild: context.guild!),
              EmbedFieldBuilder(name: "Reason", value: reason?.data ?? "No reason provided.", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("kick", "Moderation", "Kick a user.", (T context, Member member, [GreedyString? reason]) async {
        try {
          if (await confirm(context, "kick ${await confirmstringify(member, context.client)}") == false) return;
          final settings = ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id));
          var deleteMessagesSeconds = settings?.kickMessageRemovalSeconds.get();
          if (deleteMessagesSeconds == null || deleteMessagesSeconds <= 0) deleteMessagesSeconds = null;
          await member.manager.delete(member.id, auditLogReason: "${context.user.username}: ${reason?.data ?? "No reason provided"} (kick)");
        } on HttpResponseError catch (e) {
          Logger.warn("Kick", "Unable to kick ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Kick ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        Modlog.add(ModlogEvent(
          "mod.kick",
          title: "Kick User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.severe,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Kicked ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, member.id, guild: context.guild!),
              EmbedFieldBuilder(name: "Reason", value: reason?.data ?? "No reason provided.", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }),
      BotCommand("softban", "Moderation", "Ban then unban a user.", (T context, Member member, [GreedyString? reason]) async {
        try {
          if (await confirm(context, "softban ${await confirmstringify(member, context.client)}") == false) return;
          final settings = ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id));
          var deleteMessagesSeconds = settings?.kickMessageRemovalSeconds.get();
          if (deleteMessagesSeconds == null || deleteMessagesSeconds <= 0) deleteMessagesSeconds = null;
          await member.ban(auditLogReason: "${context.user.username}: ${reason?.data ?? "No reason provided"} (soft-ban)", deleteMessages: deleteMessagesSeconds != null ? Duration(seconds: deleteMessagesSeconds) : null);
          await member.unban();
        } on HttpResponseError catch (e) {
          Logger.warn("Softban", "Unable to soft-ban ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Soft-Ban ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n${reason?.toDiscordCodeBlock() ?? "No reason provided"}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        Modlog.add(ModlogEvent(
          "mod.softban",
          title: "Soft-Banned User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.severe,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Soft-banned ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, member.id, guild: context.guild!),
              EmbedFieldBuilder(name: "Reason", value: reason?.data ?? "No reason provided.", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["sb"]),
      BotCommand("unban", "Moderation", "Unban a user.", (T context, String userId) async {
        final userIdInt = int.tryParse(userId);
        final user = userIdInt != null ? Snowflake(userIdInt) : null;
        if (user == null) return context.respondWithError("Invalid user ID: $userId");

        try {
          await context.guild!.deleteBan(user);
        } on HttpResponseError catch (e) {
          Logger.warn("Ban", "Unable to unban $user: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to Unban ${user.value.toMention()}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        Modlog.add(ModlogEvent(
          "mod.unban",
          title: "Unbanned User",
          fields: {
            "Target": user.value.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Unbanned ${user.value.toMention()}",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, user, guild: context.guild!),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod),
      BotCommand("timeout", "Moderation", "Time out a user.", (T context, Member member, Duration duration, [GreedyString? reason]) async {
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

        Modlog.add(ModlogEvent(
          "mod.timeout",
          title: "Timed Out User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
            "Duration": duration.toString().toDiscordCodeBlock(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.warning,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Timed out ${member.toMention()} for ${duration.pretty()}\n${await memberToString(member, client: context.client, detailed: true)}",
            fields: [
              warnsToField(store, member.id, guild: context.guild!),
              EmbedFieldBuilder(name: "Reason", value: reason?.data ?? "No reason provided.", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["to"]),
      BotCommand("quicktimeout", "Moderation", "Quickly time out a user, by either passing them to this function or replying to a message of theirs.", (T context, [Member? member]) async {
        final duration = Duration(minutes: 5);

        if (member == null && context is MessageChatContext) {
          final reply = context.message.referencedMessage;
          final author = reply?.author is User ? reply!.author as User : null;
          member = await tryCatchA<Member?>(() => userToMember(author, guild: context.guild));
        }

        if (member == null) {
          return context.respondWithError("No member found.");
        }

        try {
          await member.update(MemberUpdateBuilder(communicationDisabledUntil: DateTime.now().add(duration).toUtc()), auditLogReason: "${context.user.username}: Quick timeout");
        } on HttpResponseError catch (e) {
          Logger.warn("QuickTimeout", "Unable to quick time out ${member.id}: $e");
          final fail = e.message;

          await context.respond(MessageBuilder(embeds: [
            EmbedBuilder(
              description: "## Unable to quick-time out ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}\n\n${fail.toDiscordCodeBlock()}",
              color: await getColor(context.member),
            ),
          ]));

          return;
        }

        Modlog.add(ModlogEvent(
          "mod.timeout",
          title: "Quick Timed Out User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
            "Duration": duration.toString().toDiscordCodeBlock(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.warning,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Quick-timed out ${member.toMention()} for ${duration.pretty()}\n${await memberToString(member, client: context.client, detailed: true)}",
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["tq", "qt", "qto", "toq", "quickto"], extendedDescription: "This command times someone out for 5 minutes. You can use this command in 2 ways:\n\n- Passing the user you're targeting as the only argument to the command.\n- Replying to a message by the user you're targeting."),
      BotCommand("timein", "Moderation", "Remove timeout of a user.", (T context, Member member) async {
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

        Modlog.add(ModlogEvent(
          "mod.timein",
          title: "Removed Timeout of User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: "## Removed timeout of ${member.toMention()}\n${await memberToString(member, client: context.client, detailed: true)}",
            color: await getColor(context.member),
            fields: [
              warnsToField(store, member.id, guild: context.guild!),
            ].whereType<EmbedFieldBuilder>().toList(),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["untimeout", "remtimeout", "ti"]),
      BotCommand("warns", "Moderation", "See someone's warns.", (T context, Member member) async {
        final settings = UserPerServerSettings(store, context.guild!.id, member.id);
        final warns = settings.warns.get() ?? [];
        if (warns.isEmpty) return context.respondWithError("No warns for ${await memberToString(member, client: context.client)}!");

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "Warns for ${await memberToString(member, client: context.client)}",
          footer: ElementBasedEmbedFooterBuilder(elements: ["${warns.length} Warns"]),
          pages: EmbedPage.generate(warns.mapIndexed((i, x) => EmbedFieldBuilder(name: "${i + 1}. ${x.timestamp.toDiscordTimestamp(DiscordTimestamp.longDateTime)}", value: x.reason ?? "No reason provided", isInline: false)).toList()),
          color: await getColor(context.member),
        ), settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["listwarns", "wl"]),
      BotCommand("warn", "Moderation", "Warn someone.", (T context, Member member, [GreedyString? reason]) async {
        if (await confirm(context, "warn ${await confirmstringify(member, context.client)}") == false) return;
        final settings = UserPerServerSettings(store, context.guild!.id, member.id);
        final warns = settings.warns.get() ?? [];
        final warn = Warn(timestamp: DateTime.now().toUtc(), reason: reason?.data);

        warns.add(warn);
        settings.warns.set(warns);

        Modlog.add(ModlogEvent(
          "mod.warn",
          title: "Warned User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
            "Reason": reason?.data.toDiscordCodeBlock() ?? "No reason provided",
            "Timestamp": warn.timestamp.toUtc().toIso8601String().toDiscordCodeBlock(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.warning,
        ));

        await context.respond(MessageBuilder(content: "Warned ${await memberToString(member, client: context.client)}. This is warn **#${warns.length}**.\n${reason ?? "No reason provided."}"));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["w"]),
      BotCommand("unwarn", "Moderation", "Remove a warn from someone", (T context, Member member, [int? index]) async {
        final settings = UserPerServerSettings(store, context.guild!.id, member.id);
        final warns = settings.warns.get() ?? [];
        index ??= warns.length;
        if (warns.isEmpty || warns.length < index || index < 1) return context.respondWithError("No warns for index $index.");

        warns.removeAt(index - 1);
        settings.warns.set(warns);

        Modlog.add(ModlogEvent(
          "mod.unwarn",
          title: "Removed Warn from User",
          fields: {
            "Target": member.toMention(),
            "Author": context.user.toMention(),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.good,
        ));

        await context.respond(MessageBuilder(content: "Removed warn **#$index** for ${await memberToString(member, client: context.client)}."));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["remwarn", "uw"]),
      BotCommand("summary", "Moderation", "Get a moderation summary of a user.", (T context, Member member) async {
        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            description: await memberToString(member, client: context.client, detailed: true),
            fields: [
              warnsToField(store, member.id, force: true, guild: context.guild!),
              EmbedFieldBuilder(name: "Timeout", value: "Until ${member.communicationDisabledUntil?.toDiscordTimestamp(DiscordTimestamp.shortDateTime) ?? "never"} (${member.communicationDisabledUntil?.toDiscordTimestamp(DiscordTimestamp.relative) ?? "never"})", isInline: false),
            ].whereType<EmbedFieldBuilder>().toList(),
            color: await getColor(context.member),
          ),
        ]));
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["s"]),
      BotCommand("purge", "Moderation", "Purge messages from a channel. Messages must be under 14 days old.", (T context, int amount, [GreedyString? args]) async {
        if (await context.assureGuild() == false) return;
        if (amount <= 2) return context.respondWithError("Too little messages. Must be greater than 2.");
        final m = await context.respond(MessageBuilder(content: "Purging $amount messages..."));
        final channel = context.channel as GuildTextChannel;

        final Map<String, Object?> arguments = args != null ? parseArgs(args.data) : {};
        bool quiet = arguments.containsKey("quiet");

        var messages = (await channel.messages.fetchManyUnlimited(amount)).where((x) => x.timestamp.isBefore(m.timestamp)).toList();
        Logger.print("Purge", "Found ${messages.length} messages from $amount requested");
        if (messages.length < 2) return context.respondWithError("Only found **${messages.length}** valid messages.${messages.isNotEmpty ? "\n${messages.map((x) => discordLink(context.guild?.id, x.channelId, x.id))}" : ""}", level: ResponseLevel.hint);

        if (arguments["userIds"] is List<Snowflake>) {
          final ids = arguments["userIds"] as List<Snowflake>;
          messages.removeWhere((x) => !ids.contains(x.author.id));
        }

        if (arguments["notUserIds"] is List<Snowflake>) {
          final ids = arguments["notUserIds"] as List<Snowflake>;
          messages.removeWhere((x) => ids.contains(x.author.id));
        }

        if (arguments["inTheLast"] is Duration) {
          final duration = arguments["inTheLast"] as Duration;
          final after = DateTime.now().subtract(duration);
          messages.removeWhere((x) => x.timestamp.toUtc().isBefore(after));
        }

        if (arguments["after"] is DateTime) {
          final date = arguments["after"] as DateTime;
          messages.removeWhere((x) => !x.timestamp.toUtc().isAfter(date));
        }

        if (arguments["before"] is DateTime) {
          final date = arguments["before"] as DateTime;
          messages.removeWhere((x) => !x.timestamp.toUtc().isBefore(date));
        }

        if (arguments["limit"] is int) {
          messages = messages.sorted((a, b) => b.timestamp.compareTo(a.timestamp)).sublist(0, min(arguments["limit"] as int, messages.length));
        }

        if (arguments["types"] is List<int>) {
          final types = arguments["types"] as List<int>;
          messages.removeWhere((x) => !types.contains(x.type.value));
        }

        if (arguments["notTypes"] is List<int>) {
          final types = arguments["notTypes"] as List<int>;
          messages.removeWhere((x) => types.contains(x.type.value));
        }

        if (arguments["pinned"] is bool) {
          final y = arguments["pinned"] as bool;
          messages.removeWhere((x) => y ? !x.isPinned : x.isPinned);
        }

        if (arguments["embed"] is bool) {
          final y = arguments["embed"] as bool;
          messages.removeWhere((x) => y ? x.embeds.isEmpty : x.embeds.isNotEmpty);
        }

        if (arguments["attachment"] is bool) {
          final y = arguments["attachment"] as bool;
          messages.removeWhere((x) => y ? x.attachments.isEmpty : x.attachments.isNotEmpty);
        }

        if (arguments["bot"] is bool) {
          final y = arguments["bot"] as bool;
          await context.updateMessage(m, MessageUpdateBuilder(content: "Purging $amount messages...\n-# Checking for bot value `$y`... this might take a while."));

          final results = (await Future.wait(messages.map((x) async {
            final user = await context.client.users.fetch(x.author.id);
            final isBot = user.isBot || user.isSystem;
            return (message: x, isBot: isBot);
          })));

          Logger.print("Purge", "Found ${messages.length} total messages, ${results.length} filtered messages (y=$y)");
          messages = results.where((x) => y ? x.isBot : !x.isBot).map((x) => x.message).toList();
        }

        if (arguments["contains"] is String) {
          final text = arguments["contains"] as String;
          messages.removeWhere((x) => x.content.trim().contains(text));
        }

        if (arguments["startsWith"] is String) {
          final text = arguments["startsWith"] as String;
          messages.removeWhere((x) => x.content.trim().startsWith(text));
        }

        if (arguments["endsWith"] is String) {
          final text = arguments["endsWith"] as String;
          messages.removeWhere((x) => x.content.trim().endsWith(text));
        }

        final automatic = messages.where((x) => DateTime.now().difference(x.timestamp) < Duration(days: 14)).toList();
        final manual = messages.where((x) => DateTime.now().difference(x.timestamp) >= Duration(days: 14)).toList();

        //await Future.wait(messages.map((x) => x.react(ReactionBuilder(name: "🎯", id: null))));
        final confirmResult = await confirm(context, "purge ${messages.length} messages (${automatic.length} automatic, ${manual.length} manual)", deleteUserConfirmationInput: quiet);

        if (!confirmResult) {
          await Future.wait(messages.map((x) => x.deleteReaction(ReactionBuilder(name: "🎯", id: null), userId: context.client.user.id)));
          return;
        }

        final preview = arguments.containsKey("preview");
        await context.updateMessage(m, MessageUpdateBuilder(content: "Purging ${automatic.length} messages..."));
        if (!preview && automatic.length > 1) await purge(channel, automatic);
        if (automatic.length == 1) await automatic.first.delete();

        await context.updateMessage(m, MessageUpdateBuilder(content: "Purging ${manual.length} messages manually..."));
        if (!preview) await Future.wait(manual.map((x) => tryCatchA(() => x.delete())));

        final m2 = await context.channel.sendMessage(MessageBuilder(content: [
          "Purged ${messages.length} messages.",
          if (dev) arguments.entries.map((x) => "-# `${x.key}`: `${x.value}`").join("\n"),
        ].join("\n")));

        if (quiet) {
          await tryCatchA(() => m.delete());
          await tryCatchA(() => m2.delete());
        }

        Modlog.add(ModlogEvent(
          "mod.purge",
          title: "Purged Messages",
          fields: {
            "Channel": channel.toMention(),
            "Amount": "$amount -> ${messages.length} (automatic: ${automatic.length}, manual: ${manual.length})".toDiscordCodeString(),
            "Author": context.user.toMention(),
            "Arguments": arguments.entries.map((x) => "- ${x.key.toDiscordCodeString()}: ${x.value.toDiscordCodeString()}").join("\n"),
          },
          guild: context.guild,
          settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)),
          client: context.client,
          severity: ModlogSeverity.severe,
        ));
      }, permissionsRequired: BotCommandPermissions.mod, extendedDescription: "Usage: `purge <amount> <args>`\nArgs (`key=\"value\"`):\n\n${{
        "limit": "Message limit. This is different from the amount fetched.",
        "userIds": "A comma-separated string of user IDs. Any messages sent by one of these IDs will be deleted.",
        "notUserIds": "A comma-separated string of user IDs. Any messages sent by none of these IDs will be deleted.",
        "before": "Messages before a date.",
        "after": "Messages after a date.",
        "inTheLast": "Filter in messages sent in the last whatever time period.",
        "contains": "If the message contains specific text.",
        "startsWith": "If the message starts with specific text.",
        "endsWith": "If the message ends with specific text.",
        "types": "A comma-separated list of integers, representing message types. Run `messagetypes` to see all message types.",
        "notTypes": "A comma-separated list of integers, representing message types. Run `messagetypes` to see all message types.",
        "pinned": "Set this to false to filter out pinned messages, or true to only delete pinned messages.",
        "bot": "Set this to false to filter out bot messages or system messages, or true to only delete said messages. Note: This is extremely expensive and not recommended.",
        "embed": "Set this to false to filter out messages without embeds, or true to only delete messages with embeds.",
        "attachment": "Set this to false to filter out messages without attachments, or true to only delete messages with attachments.",
        "quiet": "Delete the bot's results messages too.",
        if (dev) "preview": "Include this argument to not actually purge messages, but just dry-run the command.",
      }.entries.map((x) => "- `${x.key}`: ${x.value}").join("\n")}"),
      BotCommand("messagetypes", "ModerationAdmin", "See all message types and their values.", (T context) async {
        await respondWithPagination(context, settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)), PaginatedEmbedBuilder(
          pages: EmbedPage.generateFromItems(
            messageTypes.map((x) => "- `${x.value.toString().padRight(2)} ${x.name.padRight(30)} (deletable: ${"${x.deletable})".padRight(6)}`").toList(),
          ),
        ));
      }),
      BotCommand("setbanmessageremoval", "ModerationAdmin", "Set the ban message removal period.", (T context, Duration duration) async {
        if (await context.assureGuild() == false) return;
        final settings = ServerSettings(store, context.guild!.id);
        settings.banMessageRemovalSeconds.set(duration.inSeconds);
        await context.respond(MessageBuilder(content: "Set ban message removal period to **${duration.prettyDetailed()}**."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setsbmessageremoval", "ModerationAdmin", "Set the soft-ban message removal period.", (T context, Duration duration) async {
        if (await context.assureGuild() == false) return;
        final settings = ServerSettings(store, context.guild!.id);
        settings.kickMessageRemovalSeconds.set(duration.inSeconds);
        await context.respond(MessageBuilder(content: "Set soft-ban message removal period to **${duration.prettyDetailed()}**."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("messageremoval", "ModerationAdmin", "Get the ban and soft-ban message removal period.", (T context) async {
        if (await context.assureGuild() == false) return;
        final settings = ServerSettings(store, context.guild!.id);

        var banSeconds = settings.banMessageRemovalSeconds.get();
        var sbSeconds = settings.kickMessageRemovalSeconds.get();

        if (banSeconds == null || banSeconds <= 0) banSeconds = null;
        if (sbSeconds == null || sbSeconds <= 0) sbSeconds = null;

        final banDuration = banSeconds != null ? Duration(seconds: banSeconds) : null;
        final sbDuration = sbSeconds != null ? Duration(seconds: sbSeconds) : null;

        await context.respond(MessageBuilder(content: [
          "Ban message removal: **${banDuration?.prettyDetailed() ?? "Not set"}**",
          "Soft-ban message removal: **${sbDuration?.prettyDetailed() ?? "Not set"}**",
        ].join("\n")));
      }),
      BotCommand("delete", "Moderation", "Delete a message.", (ChatContext context, [Snowflake? id]) async {
        Message? message;

        if (id == null && context is MessageChatContext) {
          final reply = context.message.referencedMessage;
          message = reply;
        }

        if (id != null) {
          try {
            final channel = context.channel;
            message = await channel.messages.get(id);
          } catch (_) {}
        }

        if (message == null) return context.respondWithError("No message or input found.");
        await message.delete();

        if (context is MessageChatContext) {
          final m = await context.channel.sendMessage(MessageBuilder(content: "Deleting message `${message.id}`..."));
          await context.message.delete();
          await m.delete();
        } else if (context is InteractionChatContext) {
          await context.respond(MessageBuilder(content: "Message `${message.id}` deleted."), level: ResponseLevel.hint);
        }
      }, permissionsRequired: BotCommandPermissions.mod, aliases: ["d"]),
      BotCommand("lock", "Moderation", "Disable certain permissions for @everyone.", (T context, [GuildTextChannel? channel]) async {
        final settings = ServerSettings(store, context.guild!.id);
        final roles = settings.lockAllow.get();

        final thisChannel = channel == null;
        channel ??= context.channel as GuildTextChannel;
        final role = context.guild!.id;
        final ignored = settings.lockAllowIgnore.get().contains(channel.id);

        final existingOverwrite = channel.permissionOverwrites.firstWhereOrNull(
          (x) => x.id == role && x.type == PermissionOverwriteType.role,
        );

        final lockPermissions = Permissions.addReactions |
          Permissions.sendMessages |
          Permissions.sendMessagesInThreads |
          Permissions.createPublicThreads |
          Permissions.createPrivateThreads |
          Permissions.speak |
          Permissions.requestToSpeak |
          Permissions.stream |
          Permissions.useSoundboard;

        await channel.updatePermissionOverwrite(
          PermissionOverwriteBuilder(
            id: role,
            type: PermissionOverwriteType.role,
            deny: (existingOverwrite?.deny ?? Permissions(0)) | lockPermissions,
            allow: existingOverwrite?.allow,
          ),
        );

        if (!ignored) for (final role in roles) {
          final existingOverwrite = channel.permissionOverwrites.firstWhereOrNull(
            (x) => x.id == role && x.type == PermissionOverwriteType.role,
          );

          final currentDeny = existingOverwrite?.deny ?? Permissions(0);
          final currentAllow = existingOverwrite?.allow ?? Permissions(0);
          final toAllow = ignored ? Permissions(0) : Permissions(lockPermissions.value & ~currentDeny.value);

          await channel.updatePermissionOverwrite(
            PermissionOverwriteBuilder(
              id: role,
              type: PermissionOverwriteType.role,
              deny: currentDeny,
              allow: Permissions(currentAllow.value | toAllow.value),
            ),
          );
        }

        await context.respond(MessageBuilder(content: "${thisChannel ? "Channel" : channel.toMention()} locked.\n-# Allowed ${ignored ? 0 : roles.length} roles."));
      }, permissionsRequired: BotCommandPermissions.mod, needsGuild: true, extendedDescription: "The following permissions will be disabled for `@everyone`:\n${[
        "Send messages (including in threads)",
        "Create public/private threads",
        "Add reactions",
        "Speak/request to speak",
        "Stream",
        "Use soundboard",
      ].map((x) => "- $x").join("\n")}"),
      BotCommand("unlock", "Moderation", "Re-enable certain permissions for @everyone.", (T context, [GuildTextChannel? channel]) async {
        final thisChannel = channel == null;
        channel ??= context.channel as GuildTextChannel;
        final role = context.guild!.id;

        final existingOverwrite = channel.permissionOverwrites.firstWhereOrNull(
          (x) => x.id == role && x.type == PermissionOverwriteType.role,
        );

        final permissionsToUnlock = Permissions.addReactions |
          Permissions.sendMessages |
          Permissions.sendMessagesInThreads |
          Permissions.createPublicThreads |
          Permissions.createPrivateThreads |
          Permissions.speak |
          Permissions.requestToSpeak |
          Permissions.stream |
          Permissions.useSoundboard;

        await channel.updatePermissionOverwrite(
          PermissionOverwriteBuilder(
            id: role,
            type: PermissionOverwriteType.role,
            deny: Permissions((existingOverwrite?.deny ?? Permissions(0)).value & ~permissionsToUnlock.value),
            allow: existingOverwrite?.allow,
          ),
        );

        await context.respond(MessageBuilder(content: "${thisChannel ? "Channel" : channel.toMention()} unlocked."));
      }, permissionsRequired: BotCommandPermissions.mod, needsGuild: true, extendedDescription: "The following permissions will be re-enabled for `@everyone`:\n${[
        "Send messages (including in threads)",
        "Create public/private threads",
        "Add reactions",
        "Speak/request to speak",
        "Stream",
        "Use soundboard",
      ].map((x) => "- $x").join("\n")}"),
      BotCommand("lockallow", "ModerationAdmin", "Roles to always allow to speak when locking a channel.", (ChatContext context) async {
        final settings = ServerSettings(store, context.guild!.id);
        final roles = settings.lockAllow.get();
        final ignore = settings.lockAllow.get();
        await context.respond(MessageBuilder(content: "Lock allow roles:\n${roles.isNotEmpty ? (await Future.wait(roles.map((x) async => (x, await tryCatchA(() => context.guild!.roles.get(x)))))).map((x) => "`${x.$1}` (${x.$2?.name ?? "<Not Found>"})").join(", ").toDiscordCodeBlock() : "None set"}\n\nChannels to ignore lock allow in:\n${ignore.isNotEmpty ? ignore.map((x) => x.value.toChannel()).join(", ") : "None set"}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setlockallow", "ModerationAdmin", "Set roles to always allow to speak when locking a channel.", (ChatContext context, GreedyRoleList roles) async {
        final settings = ServerSettings(store, context.guild!.id);
        settings.lockAllow.set(roles.input.map((x) => x.id).toList());
        await context.respond(MessageBuilder(content: "Set lock allow roles!\n${roles.input.map((x) => x.name).join(", ").toDiscordCodeBlock()}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setlockallowignore", "ModerationAdmin", "Set channels to ignore lock allow settings.", (ChatContext context, GreedyGuildTextChannelList channels) async {
        final settings = ServerSettings(store, context.guild!.id);
        settings.lockAllowIgnore.set(channels.input.map((x) => x.id).toList());
        await context.respond(MessageBuilder(content: "Set lock allow ignore!\n${channels.input.map((x) => x.toMention()).join(", ")}"));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
    ];
  }

  static final Map<String, List<String>> memberUpdateProperties = {
    "assets": ["avatarUri", "bannerUri"],
    "flags": ["flags"],
    //"voice": ["deaf", "mute"],
    "membership": ["pendingMembership"],
    "name": ["username", "globalName", "nickname", "discriminator"],
    "timeout": ["communicationDisabledUntil"],
  };

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    Modlog.addIgnored({"message.send", "audit"});

    return [
      {
        ModlogGroup.all: (levelBelow) => {...levelBelow, "mod.timein", "mod.unwarn", "message.send", "audit", ...memberUpdateProperties.keys.where((x) => x != "timeout").map((x) => "member.update.$x")},
        ModlogGroup.normal: (levelBelow) => {...levelBelow, "mod.ban", "mod.unban", "mod.timeout", "mod.kick", "mod.warn", "mod.purge", "mod.softban", "message.delete", "message.edit", "member.add", "member.remove", "member.ban", "member.unban", "message.bulkdelete", "invite.create", "invite.delete", "member.update.timeout", "mod.block.set", "mod.block.catch", "channel.lock", "channel.unlock", "channel.slowmode"},
        ModlogGroup.quiet: (levelBelow) => {...levelBelow},
        ModlogGroup.off: (_) => {},
      },
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onMessageCreate.listen((event) async {
        if (event.message.author.id == client.user.id) return;

        Modlog.add(ModlogEvent(
          "message.send",
          title: "Message Sent",
          fields: {
            "Author": event.message.author.id.value.toMention(),
            "ID": event.message.id.toDiscordCodeString(),
            "Link": "https://discord.com/channels/${[event.guildId ?? "@me", event.message.channelId, event.message.id].join("/")}",
            "Attachments": "${event.message.embeds.length} embeds, ${event.message.attachments.length} attachments",
            "Timestamp": event.message.timestamp.toDiscordTimestamp(DiscordTimestamp.longDateTime),
            "Content": event.message.content.toDiscordCodeBlock(language: null),
          },
          guild: await event.guild?.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
        ));
      });

      client.onMessageUpdate.listen((event) async {
        if (event.message.author.id == client.user.id) return;
        final old = event.oldMessage;
        if (old != null && old.content == event.message.content) return;

        final author = event.message.author;
        if (author is! User) return;
        if (author.isBot || author.isSystem) return;

        Modlog.add(ModlogEvent(
          "message.edit",
          title: "Message Edited",
          fields: {
            "Author": author.id.value.toMention(),
            "ID": event.message.id.toDiscordCodeString(),
            "Link": "https://discord.com/channels/${[event.guildId ?? "@me", event.message.channelId, event.message.id].join("/")}",
            "Embeds": "${old?.embeds.length} -> ${event.message.embeds.length}".toDiscordCodeString(),
            "Attachments": "${old?.attachments.length} -> ${event.message.attachments.length}".toDiscordCodeString(),
            "Timestamp": event.message.editedTimestamp?.toDiscordTimestamp(DiscordTimestamp.longDateTime) ?? "No timestamp",
            "Was": old?.content.toDiscordCodeBlock(language: "md") ?? "Not found",
            "Content": event.message.content.toDiscordCodeBlock(language: "md"),
          },
          guild: await event.guild?.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
        ));
      });

      client.onMessageDelete.listen((event) async {
        final old = event.deletedMessage ?? event.channel.messages.cache[event.id];

        Modlog.add(ModlogEvent(
          "message.delete",
          title: "Message Deleted",
          fields: {
            "Author": event.deletedMessage?.author.id.value.toMention() ?? "No author found",
            "ID": event.id.toDiscordCodeString(),
            "Was": old?.content.toDiscordCodeBlock(language: "md") ?? "Not found",
          },
          guild: await event.guild?.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
        ));
      });

      client.onMessageBulkDelete.listen((event) async {
        final old = Map.fromEntries(event.ids.map((x) => MapEntry(x, event.deletedMessages.firstWhereOrNull((y) => y.id == x))));

        Modlog.add(ModlogEvent(
          "message.bulkdelete",
          title: "Messages Bulk Deleted",
          fields: {
            "Amount": "${event.ids.length} IDs, ${event.deletedMessages.length} messages found in cache",
            "Channel": event.channelId.value.toChannel(),
          },
          guild: await event.guild?.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
          attachments: {
            "messages.md": [
              (await Future.wait(old.entries.map((x) async => "- ${x.key}: ${x.value == null ? "Message not found in cache" : await (() async {
                final message = x.value!;
                final author = message.author;

                return [
                  "By ${author is User ? await userToString(author) : (author is WebhookAuthor ? "${author.username} (`${author.id}`)" : "Invalid user")} (`${author.runtimeType}`)",
                  "Sent at `${message.timestamp.toUtc().toIso8601String()}`, edited at `${message.editedTimestamp?.toUtc().toIso8601String() ?? 'never'}`",
                  "Mentions: ${[...await Future.wait(message.mentions.map((x) => userToString(x).toFuture())), if (message.mentionsEveryone) "@everyone"].join(", ")}",
                  "${message.embeds.length} embeds, ${message.attachments.length} attachments",
                ].join(" - ");
              }())}"))).join("\n"),
              (await Future.wait(old.entries.where((x) => x.value != null).map((x) async => "## Message ${x.key} by ${await userToString(await tryCatchA(() => client.users.get(x.key)))}\n${x.value?.content}"))).join("\n\n---\n\n"),
            ].join("\n\n\n"),
          },
          severity: ModlogSeverity.severe,
        ));
      });

      client.onGuildAuditLogCreate.listen((event) async {
        Modlog.add(ModlogEvent(
          "audit",
          title: "Audit Log Update",
          fields: {
            "Action Type": event.entry.actionType.toDiscordCodeString(),
            "Target": event.entry.targetId.toDiscordCodeString(),
            "Author": event.entry.userId?.value.toMention() ?? "No author",
            "Reason": event.entry.reason ?? "No reason",
            "ID": event.entry.id.toDiscordCodeString(),
            "Updates": event.entry.changes?.map((x) {
              return "${x.key}: ${x.oldValue} -> ${x.newValue}";
            }).toDiscordCodeBlock() ?? "No updates",
          },
          guild: await event.guild.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
        ));
      });

      client.onGuildMemberAdd.listen((event) async {
        bool? blocked = false;
        final settings = UserPerServerSettings(context.store, event.guildId, event.member.id);

        if (settings.blocked.get()) {
          try {
            await event.member.ban(auditLogReason: "User is blocked.");
            settings.blocked.set(true);
            blocked = true;
          } catch (e) {
            Logger.warn("Moderation", "Unable to ban after block ${event.member.id}: $e");
            blocked = null;
          }
        }

        Modlog.add(ModlogEvent(
          "member.add",
          title: "Member Added",
          fields: {
            "Member": event.member.toMention(),
            "Block": blocked == false ? "Not blocked" : (
              blocked == true ? "User has been banned because they were blocked.\nThey will be unblocked, but will still be banned." : "User was unable to be banned."
            ),
          },
          guild: await event.guild.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
          severity: blocked == false ? ModlogSeverity.good : ModlogSeverity.severe,
          alsoTriggerOn: [if (blocked != false) "mod.block.catch"],
        ));
      });

      client.onGuildMemberRemove.listen((event) async {
        try {
          Modlog.add(ModlogEvent(
            "member.remove",
            title: "Member Removed",
            fields: {
              "Member": event.user.toMention(),
              "ID": event.user.id.toDiscordCodeString(),
            },
            guild: await event.guild.get(),
            settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
            client: client,
          ));
        } catch (_) {}
      });

      client.onGuildBanAdd.listen((event) async {
        Modlog.add(ModlogEvent(
          "member.ban",
          title: "Member Banned",
          fields: {
            "Member": event.user.toMention(),
            "ID": event.user.id.toDiscordCodeString(),
          },
          guild: await event.guild.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
          severity: ModlogSeverity.severe,
        ));
      });

      client.onGuildBanRemove.listen((event) async {
        Modlog.add(ModlogEvent(
          "member.unban",
          title: "Member Unbanned",
          fields: {
            "Member": event.user.toMention(),
            "ID": event.user.id.toDiscordCodeString(),
          },
          guild: await event.guild.get(),
          settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
          client: client,
          severity: ModlogSeverity.good,
        ));
      });

      client.onGuildMemberUpdate.listen((event) async {
        final member = event.oldMember;
        if (member == null) return;
        final user = event.oldMember?.user;

        final List<(String name, String? value) Function(Member member)> memberProperties = [
          (x) => ("flags", x.flags.map((f) => f.value).sorted((a, b) => a.compareTo(b)).join(",")),
          (x) => ("nickname", x.nick),
          (x) => ("deaf", x.isDeaf.toString()),
          (x) => ("mute", x.isMute.toString()),
          (x) => ("pendingMembership", x.isPending.toString()),
          (x) => ("communicationDisabledUntil", x.communicationDisabledUntil?.toIso8601String()),
        ];

        final List<(String name, String? value) Function(User user)> userProperties = [
          (x) => ("avatarUri", x.avatar.url.toString()),
          (x) => ("bannerUri", x.banner?.url.toString()),
          (x) => ("globalName", x.globalName),
          (x) => ("username", x.username),
          (x) => ("discriminator", x.discriminator),
        ];

        List<(int type, String name, dynamic a, dynamic b)> changedProperties = [];

        String typeToString(int type) => switch (type) {
          0 => "Member",
          1 => "User",
          int() => throw UnimplementedError(),
        };

        if (user != null && event.member.user != null) for (final x in userProperties) {
          final a = x.call(user);
          final b = x.call(event.member.user!);
          if (a != b) changedProperties.add((0, a.$1, a.$2, b.$2));
        }

        for (final x in memberProperties) {
          final a = x.call(member);
          final b = x.call(event.member);
          if (a != b) changedProperties.add((1, a.$1, a.$2, b.$2));
        }

        for (final property in memberUpdateProperties.entries) {
          final keys = property.value;
          final changed = changedProperties.where((x) => keys.contains(x.$2));
          if (changed.isEmpty) continue;

          Modlog.add(ModlogEvent(
            "member.update.${property.key}",
            title: "Member Updated (${property.key})",
            fields: Map.fromEntries(changed.map((x) {
              return MapEntry("`${typeToString(x.$1)}` `${x.$2}`", "${x.$3} -> ${x.$4}".toDiscordCodeBlock());
            })),
            guild: await event.guild.get(),
            settings: ifGuild(context.store, event.guildId, (id) => ServerSettings(context.store, id)),
            client: client,
          ));
        }
      });

      client.onInviteCreate.listen((event) async {
        if (event.invite.guild == null) return;
        final guild = await event.invite.guild!.get();

        Modlog.add(ModlogEvent(
          "invite.create",
          title: "Invite Created",
          fields: {
            "ID": "[${event.invite.code.toDiscordCodeString()}](https://discord.gg/${event.invite.code})",
            "Channel": event.invite.channel.id.value.toChannel(),
            "Timestamp": event.invite.createdAt.toDiscordTimestamp(DiscordTimestamp.shortDateTime),
            "Uses": event.invite.uses.toString(),
            "Max Uses": event.invite.maxUses.toString(),
            "Max Age": "${event.invite.maxAge.toDiscordCodeString()} (at ${(event.invite.expiresAt ?? DateTime.now().add(event.invite.maxAge)).toDiscordTimestamp(DiscordTimestamp.shortDateTime)})",
            "Temporary": event.invite.isTemporary.toDiscordCodeString(),
            "Author": await userToString(event.invite.inviter) ?? null.toDiscordCodeString(),
            "Type": event.invite.type.value.toDiscordCodeString(),
            "Guest Invite for Voice Channel": (event.invite.flags?.hasGuestInvite).toDiscordCodeString(),
          },
          guild: guild,
          settings: ServerSettings(context.store, guild.id),
          client: client,
          severity: ModlogSeverity.good,
        ));
      });

      client.onInviteDelete.listen((event) async {
        if (event.guild == null) return;
        final guild = await event.guild!.get();

        Modlog.add(ModlogEvent(
          "invite.delete",
          title: "Invite Deleted",
          fields: {
            "ID": event.code.toDiscordCodeString(),
            "Channel": event.channel.id.value.toChannel(),
          },
          guild: guild,
          settings: ServerSettings(context.store, guild.id),
          client: client,
        ));
      });

      client.onChannelUpdate.listen((event) async {
        if (event.channel is! GuildTextChannel || event.oldChannel is! GuildTextChannel) return;
        final channel = event.channel as GuildTextChannel;
        final oldChannel = event.oldChannel as GuildTextChannel;
        if (channel.rateLimitPerUser == oldChannel.rateLimitPerUser) return;

        Modlog.add(ModlogEvent(
          "channel.slowmode",
          title: "Channel Slowmode Updated",
          fields: {
            "From": "${oldChannel.rateLimitPerUser} (${oldChannel.rateLimitPerUser?.prettyDetailed()})".toDiscordCodeBlock(),
            "To": "${(channel.rateLimitPerUser).toDiscordCodeString()} (${channel.rateLimitPerUser?.prettyDetailed()})".toDiscordCodeBlock(),
            "Channel": channel.toMention(),
          },
          guild: await tryCatchA(() => channel.guild.get()),
          settings: ServerSettings(context.store, channel.guildId),
          client: client,
        ));
      });
    });
  }
}

@JsonSerializable(anyMap: true)
class Warn {
  final String? reason;
  final DateTime timestamp;

  Warn({required this.timestamp, required this.reason});
  factory Warn.fromJson(Map input) => _$WarnFromJson(input);
  Map toJson() => _$WarnToJson(this);

  @override
  bool operator ==(Object other) {
    return other is Warn && timestamp == other.timestamp;
  }

  @override
  int get hashCode => timestamp.hashCode;
}

EmbedFieldBuilder? warnsToField(KVStore store, Snowflake userId, {bool force = false, required Guild guild}) {
  final settings = UserPerServerSettings(store, guild.id, userId);
  final warns = settings.warns.get() ?? [];

  if (force == false && warns.isEmpty) return null;
  return EmbedFieldBuilder(name: "Warns", value: "**${warns.length}**, most recent: ${warns.firstOrNull?.timestamp.toDiscordTimestamp(DiscordTimestamp.shortDateTime) ?? "never"}", isInline: false);
}

Map<String, Object?> parseArgs(String input) {
  final regex = RegExp(r"""(\w+)=(?:"([^"]*)"|([\S]+))""");
  final matches = regex.allMatches(input);
  Map<String, Object?> result = {};

  for (final match in matches) {
    final key = match.group(1)!;
    final string = match.group(2) ?? match.group(3)!;

    switch (key) {
      case "userIds":
      case "notUserIds":
        final values = string.split(",").map((x) => x.trim()).where((x) => int.tryParse(x) != null).where((x) => int.parse(x) > 0).map((x) => Snowflake(int.parse(x))).toList();
        result[key] = values;
        break;
      case "inTheLast":
        final value = parseDuration(string);
        if (value == null) continue;
        result[key] = value;
      case "contains":
      case "startsWith":
      case "endsWith":
        result[key] = string.trim();
      case "limit":
        final x = int.tryParse(string);
        if (x != null) result[key] = x;
      case "types":
      case "notTypes":
        final values = string.split(",").map((x) => x.trim()).where((x) => int.tryParse(x) != null).where((x) => int.parse(x) > 0).map((x) => int.parse(x)).toList();
        result[key] = values;
        break;
      case "pinned":
      case "bot":
      case "embed":
      case "attachment":
        final x = switch (string.trim()) {
          "true" => true,
          "false" => false,
          String() => null,
        };

        if (x != null) result[key] = x;
        break;
      case "before":
      case "after":
        final x = DateTime.tryParse(string) ?? Chrono.parseDate(string);
        if (x != null) result[key] = x.isUtc ? x : x.toUtc();
        break;
      case "preview":
        if (dev) result[key] = string;
        break;
      case "quiet":
        result[key] = string;
        break;
    }
  }

  return result;
}

Future<void> purge(GuildTextChannel channel, List<Message> messages) async {
  final ids = messages.map((m) => m.id).toList();

  for (int i = 0; i < ids.length; i += 100) {
    final chunk = ids.sublist(i, min(i + 100, ids.length));
    await channel.messages.bulkDelete(chunk);
    await Future.delayed(Duration(seconds: 1));
  }
}

/// https://docs.discord.com/developers/resources/message
final messageTypes = """
DEFAULT 0 true
RECIPIENT_ADD 1 false
RECIPIENT_REMOVE 2 false
CALL 3 false
CHANNEL_NAME_CHANGE 4 false
CHANNEL_ICON_CHANGE 5 false
CHANNEL_PINNED_MESSAGE 6 true
USER_JOIN 7 true
GUILD_BOOST 8 true
GUILD_BOOST_TIER_1 9 true
GUILD_BOOST_TIER_2 10 true
GUILD_BOOST_TIER_3 11 true
CHANNEL_FOLLOW_ADD 12 true
GUILD_DISCOVERY_DISQUALIFIED 14 true
GUILD_DISCOVERY_REQUALIFIED 15 true
GUILD_DISCOVERY_GRACE_PERIOD_INITIAL_WARNING 16 true
GUILD_DISCOVERY_GRACE_PERIOD_FINAL_WARNING 17 true
THREAD_CREATED 18 true
REPLY 19 true
CHAT_INPUT_COMMAND 20 true
THREAD_STARTER_MESSAGE 21 false
GUILD_INVITE_REMINDER 22 true
CONTEXT_MENU_COMMAND 23 true
AUTO_MODERATION_ACTION 24 true*
ROLE_SUBSCRIPTION_PURCHASE 25 true
INTERACTION_PREMIUM_UPSELL 26 true
STAGE_START 27 true
STAGE_END 28 true
STAGE_SPEAKER 29 true
STAGE_TOPIC 31 true
GUILD_APPLICATION_PREMIUM_SUBSCRIPTION 32 true
GUILD_INCIDENT_ALERT_MODE_ENABLED 36 true
GUILD_INCIDENT_ALERT_MODE_DISABLED 37 true
GUILD_INCIDENT_REPORT_RAID 38 true
GUILD_INCIDENT_REPORT_FALSE_ALARM 39 true
PURCHASE_NOTIFICATION 44 true
POLL_RESULT 46 true
""".trim().split("\n").map((x) => x.split(" ")).map((x) => (name: x[0], value: int.parse(x[1]), deletable: bool.parse(x[2].replaceAll("*", "")))).toList();