import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';

class BotManagePlugin extends BotPlugin {
  BotManagePlugin() : super(id: "botmanage", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      restartCommand<T>(),
      killCommand<T>(),
      echoDebugCommand<T>(store),
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
                  EmbedFieldBuilder(name: "stdout", value: process.stdout.toDiscordCodeBlock(), isInline: false),
                  EmbedFieldBuilder(name: "stderr", value: process.stderr.toDiscordCodeBlock(), isInline: false),
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

        if (reset) {
          try {
            final p = await Process.run("git", ["reset", "--hard"], workingDirectory: directory.path, runInShell: true);
            await dmResult("git reset", p);
            if (failed(p)) return;
          } catch (e) {
            Logger.warn("Update", "Unable to run command git reset");
            return;
          }
        }

        try {
          final p = await Process.run("git", ["pull"], workingDirectory: directory.path, runInShell: true);
          await dmResult("git pull", p);
          if (failed(p)) return;
        } catch (e) {
          Logger.warn("Update", "Unable to run command git pull");
          return;
        }

        for (int i = 0; i < pubGets; i++) {
          try {
            final p = await Process.run("dart", ["pub", "get"], workingDirectory: directory.path, runInShell: true);
            await dmResult("dart pub get ($i)", p);
            if (failed(p)) return;
          } catch (e) {
            Logger.warn("Update", "Unable to run command dart pub get ($i)");
            return;
          }
        }
      }, permissionsRequired: BotCommandPermissions.owner, extendedDescription: "The commands that will be run:\n${{
        "git reset --hard": "Reset all local changes, only if `reset` is true.",
        "git pull": "Pull Git changes.",
        "dart pub get": "Download dependencies.",
      }.entries.map((x) => "- `${x.key}`: ${x.value}").join("\n")}"),
    ];
  }

  BotCommand restartCommand<T extends ChatContext>() => BotCommand.command("restart", "Restart the bot.", (T context) async {
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
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = ServerSettings(store, context.guild!.id);
    if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

    await context.respond(MessageBuilder(
      content: text * count,
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug"));
}