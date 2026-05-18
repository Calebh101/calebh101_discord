import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:quick_listener/quick_listener.dart';
import 'package:unicode/blocks.dart';

class DebugPlugin extends BotPlugin {
  @override
  BotPluginInfo get info => BotPluginInfo(id: "debug", version: Version.parse("1.0.0A"), description: "Provides debug commands.");

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyQuotedList.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      confirmationTest(),
      testChoose(),

      BotCommand("wait", "Debug", "Wait X amount of seconds before responding.", (ChatContext context, int seconds) async {
        await Future.delayed(Duration(seconds: seconds));
        await context.respond(MessageBuilder(content: "Waited **$seconds** seconds."), level: ResponseLevel.hint);
      }, permissionsRequired: BotCommandPermissions.owner),
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
      BotCommand("printemojis", "Debug", "Emojis.", (ChatContext context, [int? required]) async {
        final results = await askForEmojis(context, required);
        final m = await context.respond(MessageBuilder(content: results != null ? "Found **${results.emojis.length}** emojis." : "No emojis found."));

        for (final Emoji emoji in results?.emojis ?? []) {
          try {
            await m.react(ReactionBuilder.fromEmoji(emoji));
          } catch (_) {}
        }
      }),
      BotCommand("stoptyping", "Debug", "Stop typing.", (ChatContext context) async {
        QuickListener("typing").broadcast();
        await context.respond(MessageBuilder(content: "Stopped typing."));
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("typing", "Debug", "Keep typing.", (ChatContext context, [int? seconds, GreedyGuildTextChannelList? targets]) async {
        List<GuildTextChannel> channels = targets?.input ?? [if (context.channel is GuildTextChannel) context.channel as GuildTextChannel];
        if (channels.isEmpty) return context.respondWithError("No channel found.");
        if (seconds == null || seconds <= 0) seconds = null;

        void trigger() async {
          for (final x in channels) {
            try {
              await x.triggerTyping();
            } catch (_) {}
          }
        }

        await context.respond(MessageBuilder(content: "Typing ${seconds != null ? "for **$seconds** seconds" : "**forever**"} in ${channels.map((x) => x.toMention()).join(", ")}."));
        int elapsed = 0;
        bool stop = false;
        trigger();

        final listener = QuickListener("typing").listen((_, _) => stop = true);

        Timer.periodic(Duration(seconds: 5), (timer) async {
          elapsed += 5;
          trigger();

          if (seconds != null && elapsed >= seconds - 5) {
            stop = true;
          }

          if (stop) {
            timer.cancel();
            listener.dispose();
            Logger.print("Typing", "Done");
          }
        });
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("stopspamming", "Debug", "Stop spamming.", (ChatContext context) async {
        QuickListener("spamming").broadcast();
        await context.respond(MessageBuilder(content: "Stopped spamming."));
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("spam", "Debug", "Spam something.", (ChatContext context, GreedyString input) async {
        void trigger() async {
          await context.channel.sendMessage(MessageBuilder(content: input.data));
        }

        await context.respond(MessageBuilder(content: "Now spamming."));
        bool stop = false;
        trigger();
        final listener = QuickListener("spamming").listen((_, _) => stop = true);

        Timer.periodic(Duration(milliseconds: 2000), (timer) async {
          trigger();

          if (stop) {
            timer.cancel();
            listener.dispose();
            Logger.print("Typing", "Done");
          }
        });
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand("scan", "Debug", "Scan a string.", (ChatContext context, GreedyString input) async {
        await context.respond(MessageBuilder(content: [
          input.data.toDiscordCodeBlock(),
          input.data.runes.map((r) {
            return "-# - `U+${r.toRadixString(16).toUpperCase().padLeft(4, "0")}` `${getUnicodeBlock(r).name}` `${getUnicodeName(r) ?? "UNKNOWN"}`";
          }).join("\n"),
        ].join("\n\n"), allowedMentions: AllowedMentions(repliedUser: true)));
      }),
      BotCommand("emoji", "Debug", "Get an emoji.", (ChatContext context, GreedyString input) async {
        final data = input.data.trim();
        final emoji = await parseEmoji(data, client: context.client, guild: context.guild);
        await context.respond(MessageBuilder(content: emoji == null ? "No emoji found.\nInput: `$data`" : "Found emoji: `${emoji.runtimeType}`\nName: `${emoji.name}`, ID: `${emoji.id}`\nInput: `$data`", allowedMentions: AllowedMentions(repliedUser: true)));
      }),
      BotCommand("react", "Debug", "React to a message.", (MessageChatContext context, GreedyString input) async {
        final target = context.message.referencedMessage ?? context.message;
        final emoji = await parseEmoji(input.data, client: context.client, guild: context.guild) ?? context.client.getTextEmoji("🚫");

        await target.react(ReactionBuilder.fromEmoji(emoji));
      }, permissionsRequired: BotCommandPermissions.owner),
      BotCommand.command("echo", "Echo the input text from the bot.", (T context, String text, [int count = 1]) async {
        if (text.length * count > 5000) return context.respondWithError("Response would've been too long.\nLength: ${text.length * count} characters");
        if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
        final settings = ServerSettings(store, context.guild!.id);
        if (await context.assurePerms(BotCommandPermissions.owner, settings) == false) return;

        await context.respond(MessageBuilder(
          content: text * count,
        ));
      }, CommandAttributes(permissionsRequired: BotCommandPermissions.owner, category: "Debug")),
      BotCommand.command("ignoreowner", "Ignore the bot owner's status temporarily.", (T context) async {
        if (!isOwner(id: context.user.id, overrideIgnoreOwner: true)) return context.respondWithError("You are not the owner of me.");
        ignoreOwner = !ignoreOwner;
        await context.respond(MessageBuilder(content: "Owner is now **${ignoreOwner ? "temporarily ignored": "unignored"}**."));
      }, CommandAttributes(category: "Debug", permissionsRequired: BotCommandPermissions.owner)),
      ...botSettingToCommands(BotSettings(store).randomSettingsObjectForTestingIdk, name: "randomsetting", category: "Debug", description: description, requiresOwnerForGet: false),
    ];
  }
}