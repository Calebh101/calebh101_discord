import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class BotManagePlugin extends BotPlugin {
  BotManagePlugin() : super(id: "botmanage", version: Version.parse("1.0.0A"));

  @override
  Future<void> onClientLoad(BotContext context) async {
    final settings = BotSettings(context.store);
    final data = settings.whoRestartedMe.get();
    settings.whoRestartedMe.delete();

    if (data == null) return;
    final client = context.clients.clients.values.firstWhereOrNull((x) => x.user.id == data.$1);
    if (client == null) return;
    late GuildTextChannel channel;

    try {
      channel = await client.channels.get(data.$2) as GuildTextChannel;
    } catch (e) {
      Logger.warn("BotManage", "Unable to get channel ${data.$2} for client ${data.$1}: $e");
      return;
    }

    try {
      await channel.sendMessage(MessageBuilder(content: "I'm back, ${data.$3.value.toMention()}!\n-# Client ID: `${data.$1}`"));
    } catch (e) {
      Logger.warn("BotManage", "Unable to send message in channel ${channel.id} for client ${data.$1} to user ${data.$3}: $e");
    }
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      restartCommand<T>(store),
      killCommand<T>(),
      echoDebugCommand<T>(store),
      ?confirmationTest(),

      BotCommand("test", "Bot", "Run tests with the bot.", (T context) async {
        await context.respond(MessageBuilder(content: "This command has not been implemented yet."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("throw", "Debug", "Throw an exception.", (ChatContext context, [int type = 0, GreedyString? message]) {
        switch (type) {
          case 0:
            throw CommandsException("${context.user.id}: ${message?.data}");
          case 1:
            throw Exception("${context.user.id}: ${message?.data}");
          default:
            return context.respondWithError("Invalid type: $type");
        }
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

  BotCommand killCommand<T extends ChatContext>() => BotCommand.command("kill", "Kill the bot. He will be sad.", (T context) async {
    if (!isOwner(id: context.user.id)) {
      context.respondWithError("You are not the owner of me!");
      return;
    }

    await context.respond(MessageBuilder(content: "I am now dead."));
    Logger.print("Commands.Kill", "User ${context.user.id} requested my death.");
    close.call();
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Bot"));

  BotCommand echoDebugCommand<T extends ChatContext>(KVStore store) => BotCommand.command("echo", "Echo the input text from the bot.", (T context, String text, [int count = 1]) async {
    if (text.length * count > 5000) return context.respondWithError("Response would've been too long.\nLength: ${text.length * count} characters");
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = ServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

    await context.respond(MessageBuilder(
      content: text * count,
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug"));
}