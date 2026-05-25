import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

const alwaysShowAliveMessage = false;

class BotManagePlugin extends BotPluginLegacy {
  BotManagePlugin() : super(id: "botmanage", version: Version.parse("1.0.0A"));

  @override
  Future<void> onClientLoad(BotContext context) async {
    Logger.print("BotManage", "Client loaded (dev=$dev)");

    () async {
      final settings = BotSettings(context.store);
      final data = settings.whoRestartedMe.get();
      final interaction = settings.lastInteraction.get();

      final client = context.clients.clients.values.firstWhereOrNull((x) => x.user.id == data?.$1 || x.user.id == interaction?.client);
      TextChannel? channel;

      try {
        channel = await client!.channels.get(data?.$2 ?? interaction!.channel) as TextChannel;
      } catch (e) {
        Logger.warn("BotManage", "Unable to get channel ${data?.$2},${interaction?.channel} for client ${data?.$1},${interaction?.client}: $e");
      }

      if (!dev || alwaysShowAliveMessage) for (final client in context.clients.clients.values) {
        await alertOwners(client, EmbedBuilder(
          title: "I'm back alive!",
          description: data != null ? "See who intentionally killed me:" : (interaction != null ? "See my last interaction:" : null),
          fields: [if (data != null) ...[
            EmbedFieldBuilder(name: "Client ID", value: "${data.$1.toDiscordCodeString()} (${data.$1.value.toMention()})", isInline: false),
            EmbedFieldBuilder(name: "Channel", value: "${data.$2.toDiscordCodeString()} (${channel is GuildTextChannel ? discordLink(channel.guildId, channel.id) : "No link available"}) (${channel.runtimeType.toDiscordCodeString()})", isInline: false),
            EmbedFieldBuilder(name: "User", value: "${data.$3.toDiscordCodeString()} (${data.$3.value.toMention()})", isInline: false),
          ] else if (interaction != null) ...[
            EmbedFieldBuilder(name: "Client ID", value: "${interaction.client.toDiscordCodeString()} (${interaction.client.value.toMention()})", isInline: false),
            EmbedFieldBuilder(name: "Channel", value: "${interaction.channel.toDiscordCodeString()} (${channel is GuildTextChannel ? discordLink(channel.guildId, channel.id) : "No link available"}) (${channel.runtimeType.toDiscordCodeString()})", isInline: false),
            EmbedFieldBuilder(name: "User", value: "${interaction.user.toDiscordCodeString()} (${interaction.user.value.toMention()})", isInline: false),
            EmbedFieldBuilder(name: "Command", value: interaction.command.toDiscordCodeString(), isInline: true),
            EmbedFieldBuilder(name: "Context", value: interaction.context.toDiscordCodeString(), isInline: true),
            EmbedFieldBuilder(name: "Input", value: interaction.input.toDiscordCodeBlock(), isInline: false),
          ]].nullIfEmpty?.toList(),
          timestamp: DateTime.now().toUtc(),
          color: DiscordColor.parseHexString("#44CC44")
        ));
      }

      settings.whoRestartedMe.delete();
      if (data == null || client == null || channel == null) return;

      try {
        if (!dev) await channel.sendMessage(MessageBuilder(content: "I'm back, ${data.$3.value.toMention()}!"));
      } catch (e) {
        Logger.warn("BotManage", "Unable to send message in channel ${channel.id} for client ${data.$1} to user ${data.$3}: $e");
      }
    }();

    context.clients.run((client) {
      final Set<Snowflake> knownGuilds = {};

      client.onReady.listen((ReadyEvent event) {
        for (final guild in event.guilds) {
          knownGuilds.add(guild.id);
        }
      });

      client.onGuildCreate.listen((event) async {
        Logger.print("Bot", "Joined guild ${event.guild.id}");
        if (knownGuilds.contains(event.guild.id)) return;
        final guild = await event.guild.fetch(withCounts: true);

        final settings = BotSettings(context.store);
        final blocked = settings.blockedGuilds.get().contains(event.guild.id);
        final blockedOwner = settings.blockedGuildOwners.get().contains(guild.ownerId);

        await alertOwners(client, EmbedBuilder(
          title: "Guild Joined",
          fields: [
            EmbedFieldBuilder(name: "Name", value: guild.name, isInline: true),
            EmbedFieldBuilder(name: "ID", value: guild.id.toDiscordCodeString(), isInline: true),
            EmbedFieldBuilder(name: "Owner", value: "${guild.ownerId.value.toMention()} (`${guild.ownerId}`)", isInline: false),
            EmbedFieldBuilder(name: "Members", value: guild.approximateMemberCount.toDiscordCodeString(), isInline: true),
            EmbedFieldBuilder(name: "Blocked", value: [
              if (blocked) "Guild",
              if (blockedOwner) "Owner",
            ].nullIfEmpty?.join(", ") ?? "Not blocked", isInline: true),
          ],
        ));

        if (blocked || blockedOwner) {
          Logger.warn("Bot", "Blocked: ${blocked ? "guild" : "0"}, ${blockedOwner ? "owner" : "0"} (owner: ${guild.ownerId})");
          await guild.leave();
        }
      });

      client.onGuildDelete.listen((event) async {
        Logger.print("Bot", "Left guild ${event.deletedGuild?.id},${event.guild.id}");
        final guild = event.deletedGuild;

        await alertOwners(client, EmbedBuilder(
          title: "Guild Left",
          fields: [
            if (guild != null) EmbedFieldBuilder(name: "Name", value: guild.name, isInline: true),
            EmbedFieldBuilder(name: "ID", value: event.guild.id.toDiscordCodeString(), isInline: true),
            if (guild != null) EmbedFieldBuilder(name: "Owner", value: "${guild.ownerId.value.toMention()} (`${guild.ownerId}`)", isInline: false),
            if (guild != null) EmbedFieldBuilder(name: "Members", value: guild.approximateMemberCount.toDiscordCodeString(), isInline: true),
            if (guild != null) EmbedFieldBuilder(name: "Source", value: event.deletedGuild != null ? "`deletedGuild`" : "`guild`", isInline: true),
          ],
        ));
      });

      if (dev) client.onMessageCreate.listen((event) async {
        if (!isOwner(id: event.message.author.id)) return;
        if (event.message.content.trim().toLowerCase() != "rst") return;

        final settings = BotSettings(context.store);
        settings.whoRestartedMe.set((client.user.id, event.message.channel.id, event.message.author.id));

        try {
          await event.message.channel.sendMessage(MessageBuilder(content: "Restarting...", referencedMessage: MessageReferenceBuilder.reply(messageId: event.message.id)));
        } catch (e) {
          Logger.warn("Restart", "Unable to reply to message ${event.message.id}: $e");
          return;
        }

        Logger.print("Restart", "User ${event.message.author.id} requested my restart.");
        await close.call(ExitCode.restart);
      });
    });
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [GreedyQuotedList.converter()];
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      restartCommand<T>(store),
      killCommand<T>(store),
      ...botSettingToCommands(BotSettings(store).inviteLink, name: "botinvite", category: "Bot", description: "Invite link to add this bot to a guild/server.", private: true),

      BotCommand("blockguild", "Bot", "Block the bot from joining a guild.", (ChatContext context, Snowflake id) async {
        final settings = BotSettings(store);
        final current = settings.blockedGuilds.get();
        current.add(id);
        settings.blockedGuilds.set(current);
        await context.respond(MessageBuilder(content: "Blocked guild `$id`."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("blockowner", "Bot", "Block the bot from joining any guild owned by someone.", (ChatContext context, Snowflake id) async {
        final settings = BotSettings(store);
        final current = settings.blockedGuildOwners.get();
        current.add(id);
        settings.blockedGuildOwners.set(current);
        await context.respond(MessageBuilder(content: "Blocked owner `$id` (${id.value.toMention()})."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("unblockguild", "Bot", "Allow the bot to join a guild.", (ChatContext context, Snowflake id) async {
        final settings = BotSettings(store);
        final current = settings.blockedGuilds.get();

        if (!current.contains(id)) {
          return context.respondWithError("This guild is not blocked.");
        }

        current.remove(id);
        settings.blockedGuilds.set(current);
        await context.respond(MessageBuilder(content: "Unblocked guild `$id`."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("unblockowner", "Bot", "Allow the bot to join ant guild owned by someone.", (ChatContext context, Snowflake id) async {
        final settings = BotSettings(store);
        final current = settings.blockedGuildOwners.get();

        if (!current.contains(id)) {
          return context.respondWithError("This owner is not blocked.");
        }

        current.remove(id);
        settings.blockedGuildOwners.set(current);
        await context.respond(MessageBuilder(content: "Unblocked owner `$id`."));
      }, permissionsRequired: BotCommandPermissions.owner),

      BotCommand("update", "Bot", "Update the bot's code. A restart will be required to apply.", (T context, [bool reset = false]) async {
        final int pubGets = 2;
        final directory = Directory.current;

        Future<bool> dmResult(String name, ProcessResult process) async {
          try {
            final channel = await context.client.users.createDm(context.user.id);

            await channel.sendMessage(MessageBuilder(embeds: [
              EmbedBuilder(
                title: "Process $name",
                timestamp: DateTime.now().toUtc(),
                fields: [
                  EmbedFieldBuilder(name: "PID", value: process.pid.toDiscordCodeString(), isInline: true),
                  EmbedFieldBuilder(name: "Exit Code", value: process.exitCode.toDiscordCodeString(), isInline: true),
                  EmbedFieldBuilder(name: "stdout", value: process.stdout.toString().toDiscordCodeBlock(), isInline: false),
                  EmbedFieldBuilder(name: "stderr", value: process.stderr.toString().toDiscordCodeBlock(), isInline: false),
                ],
                color: DiscordColor.parseHexString(process.exitCode == 0 ? "#90EE90" : "#FF7F7F"),
              ),
            ]));

            return true;
          } catch (e) {
            Logger.warn("Update", "Unable to send DM for process $name: $e");
            return false;
          }
        }

        bool failed(ProcessResult p) => p.exitCode != 0;
        final m = await context.respond(MessageBuilder(content: "Updating..."));

        Future<void> fail() async {
          await context.updateMessage(m, MessageUpdateBuilder(content: "Update failed."));
        }

        if (reset) {
          try {
            Logger.print("Update", "Running command: git reset --hard");
            final p = await Process.run("git", ["reset", "--hard"], workingDirectory: directory.path);
            if (p.stdout.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stdout:\n${p.stdout}");
            if (p.stderr.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stderr:\n${p.stderr}");
            await dmResult("git reset", p);
            if (failed(p)) return await fail();
          } catch (e) {
            Logger.warn("Update", "Unable to run command git reset");
            return await fail();
          }
        }

        try {
          Logger.print("Update", "Running command: git pull");
          final p = await Process.run("git", ["pull"], workingDirectory: directory.path);
          if (p.stdout.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stdout:\n${p.stdout}");
          if (p.stderr.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stderr:\n${p.stderr}");
          await dmResult("git pull", p);
          if (failed(p)) return await fail();
        } catch (e) {
          Logger.warn("Update", "Unable to run command git pull");
          return await fail();
        }

        for (int i = 0; i < pubGets; i++) {
          try {
            Logger.print("Update", "Running command: dart pub get ($i)");
            final p = await Process.run("dart", ["pub", "get"], workingDirectory: directory.path, runInShell: true);
            if (p.stdout.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stdout:\n${p.stdout}");
            if (p.stderr.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stderr:\n${p.stderr}");
            await dmResult("dart pub get ($i)", p);
            if (failed(p)) return await fail();
          } catch (e) {
            Logger.warn("Update", "Unable to run command dart pub get ($i)");
            return await fail();
          }
        }

        await context.updateMessage(m, MessageUpdateBuilder(content: "Updated."));
      }, permissionsRequired: BotCommandPermissions.owner, extendedDescription: "The commands that will be run:\n${{
        "git reset --hard": "Reset all local changes, only if `reset` is true.",
        "git pull": "Pull Git changes.",
        "dart pub get": "Download dependencies.",
      }.entries.map((x) => "- `${x.key}`: ${x.value}").join("\n")}"),
      BotCommand("gitreset", "Bot", "Run get reset --hard.", (T context) async {
        if (dev) return context.respondWithError("The bot is in dev mode. You cannot run this in dev mode.");
        final directory = Directory.current;

        Future<bool> dmResult(String name, ProcessResult process) async {
          try {
            final channel = await context.client.users.createDm(context.user.id);

            await channel.sendMessage(MessageBuilder(embeds: [
              EmbedBuilder(
                title: "Process $name",
                timestamp: DateTime.now().toUtc(),
                fields: [
                  EmbedFieldBuilder(name: "PID", value: process.pid.toDiscordCodeString(), isInline: true),
                  EmbedFieldBuilder(name: "Exit Code", value: process.exitCode.toDiscordCodeString(), isInline: true),
                  EmbedFieldBuilder(name: "stdout", value: process.stdout.toString().toDiscordCodeBlock(), isInline: false),
                  EmbedFieldBuilder(name: "stderr", value: process.stderr.toString().toDiscordCodeBlock(), isInline: false),
                ],
                color: DiscordColor.parseHexString(process.exitCode == 0 ? "#90EE90" : "#FF7F7F"),
              ),
            ]));

            return true;
          } catch (e) {
            Logger.warn("Update", "Unable to send DM for process $name: $e");
            return false;
          }
        }

        bool failed(ProcessResult p) => p.exitCode != 0;
        final m = await context.respond(MessageBuilder(content: "Running..."));

        Future<void> fail() async {
          await context.updateMessage(m, MessageUpdateBuilder(content: "Run failed."));
        }

        try {
          Logger.print("GitReset", "Running command: git reset --hard");
          final p = await Process.run("git", ["reset", "--hard"], workingDirectory: directory.path);
          if (p.stdout.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stdout:\n${p.stdout}");
          if (p.stderr.toString().isNotEmpty) Logger.print("Update", "Command results (code ${p.exitCode}, pid ${p.pid}) stderr:\n${p.stderr}");
          await dmResult("git reset", p);
          if (failed(p)) return await fail();
        } catch (e) {
          Logger.warn("GitReset", "Unable to run command git reset");
          return await fail();
        }


        await context.updateMessage(m, MessageUpdateBuilder(content: "Reset."));
      }, permissionsRequired: BotCommandPermissions.owner, extendedDescription: "The commands that will be run:\n${{
        "git reset --hard": "Reset all local changes.",
      }.entries.map((x) => "- `${x.key}`: ${x.value}").join("\n")}"),
      BotCommand("leave", "Bot", "Leave a server.", (T context, [Guild? target]) async {
        final guild = target ?? context.guild;
        if (guild == null) return context.respondWithError("No guild found.");

        try {
          await guild.leave();
          await alertOwners(context.client, EmbedBuilder(title: "Left guild ${guild.id} (${guild.name})", fields: [EmbedFieldBuilder(name: "Author", value: context.user.toMention(), isInline: false)]));
        } catch (e) {
          Logger.warn("Leave", "Unable to leave ${guild.id}: $e");
          await context.respond(MessageBuilder(content: "Unable to leave guild ${guild.id.toDiscordCodeString()}.\n${e.runtimeType.toDiscordCodeBlock()}"));
        }
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("listguilds", "Bot", "List all guilds the bot is in.", (T context) async {
        final guilds = await Future.wait(context.client.guilds.cache.values.map((x) async => (guild: await x.fetch(withCounts: true), owner: await tryCatchA(() => x.owner.get()))));

        await respondWithPagination(context, PaginatedEmbedBuilder(pages:
          EmbedPage.generateFromItems(guilds.map((x) {
            return "- `${x.guild.id}`: ${x.guild.name} (${x.guild.approximateMemberCount} members, owned by user `${x.guild.ownerId}` (${x.owner?.username ?? "<User not found>"}))";
          }).toList()),
          color: await getColor(context.member),
          title: "${guilds.length} Guilds",
        ), settings: ifGuild(store, context.guild?.id, (id) => ServerSettings(store, id)));
      }),
      BotCommand("pause", "Bot", "Pause the bot's responding in this server.", (T context, [int? location]) async {
        //  > 0: guild
        // null: DMs

        location ??= context.guild?.id.value;
        if (location == null) return context.respondWithError("No location set.");

        final settings = BotSettings(store);
        final current = settings.pausedLocations.get();

        current.add(location);
        settings.pausedLocations.set(current);
        await context.respond(MessageBuilder(content: "Ignored location: `$location`"));
      }, permissionsRequired: BotCommandPermissions.owner, needsGuild: true),
      BotCommand("unpause", "Bot", "Unpause the bot's responding in this server.", (T context, [int? location]) async {
        // > 0: guild
        // = 0: DMs

        location ??= context.guild?.id.value;
        if (location == null) return context.respondWithError("No location set.");

        final settings = BotSettings(store);
        final current = settings.pausedLocations.get();
        final contained = current.contains(location);

        current.remove(location);
        settings.pausedLocations.set(current);
        await context.respond(MessageBuilder(content: "Unignored location: `$location`\nThis location ${contained ? "**was**" : "was **not**"} ignored."));
      }, permissionsRequired: BotCommandPermissions.owner, needsGuild: true),
    ];
  }

  BotCommand restartCommand<T extends ChatContext>(KVStore store) => BotCommand.command("restart", "Restart the bot.", (T context) async {
    final settings = BotSettings(store);
    settings.whoRestartedMe.set((context.client.user.id, context.channel.id, context.user.id));

    if (await context.assureOwner() == false) return;
    await context.respond(MessageBuilder(content: "Restarting..."));
    Logger.print("Commands.Kill", "User ${context.user.id} requested my restart.");
    await close.call(ExitCode.restart);
  }, CommandAttributes(category: "Bot", permissionsRequired: BotCommandPermissions.owner));

  BotCommand killCommand<T extends ChatContext>(KVStore store) => BotCommand.command("kill", "Kill the bot. He will be sad.", (T context) async {
    if (!isOwner(id: context.user.id)) {
      context.respondWithError("You are not the owner of me!");
      return;
    }

    final settings = BotSettings(store);
    settings.whoRestartedMe.set((context.client.user.id, context.channel.id, context.user.id));

    await context.respond(MessageBuilder(content: "I am now dead."));
    Logger.print("Commands.Kill", "User ${context.user.id} requested my death.");
    close.call();
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Bot"));
}