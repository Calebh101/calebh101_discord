import 'dart:async';
import 'dart:math';

import 'package:calebh101_bot/plugins/botchat.dart';
import 'package:calebh101_bot/plugins/crosspost.dart';
import 'package:calebh101_bot/plugins/github.dart';
import 'package:calebh101_bot/plugins/math.dart';
import 'package:calebh101_bot/plugins/memberrole.dart';
import 'package:calebh101_bot/plugins/quote.dart';
import 'package:calebh101_bot/plugins/remind.dart';
import 'package:calebh101_bot/plugins/rules.dart';
import 'package:calebh101_bot/plugins/selfreact.dart';
import 'package:calebh101_bot/plugins/stickyroles.dart';
import 'package:calebh101_bot/plugins/tags.dart';
import 'package:calebh101_bot/plugins/welcome.dart';
import 'package:calebh101_bot/plugins/xp.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';
import 'package:quick_listener/quick_listener.dart';
import 'package:unicode/blocks.dart';

final double maxXpPerHour = 1;
final double xpPerReaction = 0.01;
final double Function(String content) xpPerMessage = (content) => double.parse(min(content.length / 1000, 0.2).toStringAsFixed(3)); // Message length of 200+ => 0.2, 20 => 0.02, 2 => 0.02

final store = KVStore("database.db");
final tokens = BotTokenStore("settings.json");
final plugins = PluginStore();

void main(List<String> arguments) => onStart = () async {
  BotCommand.disableGroups();
  BotCommand.commandType = CommandType.textOnly;

  Modlog.addExtraGroup({
    ModlogGroup.all: (levelBelow) => {...levelBelow, "xp.add"},
    ModlogGroup.normal: (levelBelow) => {...levelBelow, "xp.levelup"},
    ModlogGroup.quiet: (levelBelow) => levelBelow,
  });

  await plugins.registerAll([
    AdminPlugin(),
    SelfReactPlugin(),
    BotManagePlugin(),
    HelpPlugin(),
    IgnorePlugin(),
    MessagesPlugin(),
    PrefixPlugin(),
    StatsPlugin(),
    XPPlugin(),
    ModerationPlugin(),
    MathPlugin(),
    ModlogPlugin(),
    RulesPlugin(),
    RemindPlugin(),
    CrosspostPlugin(),
    TagsPlugin(),
    RestrictCommandsPlugin(),
    StickyRoles(),
    BotChatPlugin(),
    WelcomePlugin(),
    MutePlugin(),
    MemberRolePlugin(),
    GitHubPlugin(),
    QuotePlugin(),
  ]);

  final context = await load(
    botName: "Kyle",
    version: Version.parse("1.0.0A"),

    owners: [calebh101],
    supportServer: calebh101Server,
    tokens: tokens.single(),
    plugins: plugins,

    argParser: (args) => args,
    args: arguments,

    primaryColor: DiscordColor.parseHexString("#00FFF0"),
    prefix: mentionOr(prefixFromServerSettings((x) => Calebh101BotServerSettings(store, x.id))),
    permissions: [...GatewayIntents.all],

    store: store,
    settings: BotSettings(store),

    converters: (plugin) => [
      StringList.converter(),
      GreedyString.converter(),
      GreedyGuildTextChannelList.converter(),
    ],

    commands: <T extends ChatContext>(plugin) => [
      BotCommand.converter((plugin) => plugin.getConverter(RuntimeType<GuildTextChannel>(), logWarn: false)),
      defaultCheck(store),

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
      }),

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

      BotCommand.command("fart", "Fart.", (T context, [int amount = 1]) async {
        if (amount != 1 && !isOwner(id: context.user.id)) return context.respondWithError("You cannot control the amount.");
        if (amount < 1) return context.respondWithError("Invalid amount: $amount");

        int rn(int min, int max) {
          // Inclusive
          return Random().nextInt(max - min + 1) + min;
        }

        String random(int min, int max, String phrase) {
          return phrase * rn(min, max);
        }

        T ro<T>(List<T> options) {
          return options[Random().nextInt(options.length)];
        }

        String maybe(String option, [int factor = 1]) {
          return ro([option, ...List.generate(factor, (_) => "")]);
        }

        final List<String Function()> farts = [
          () => "P${random(2, 20, "o")}t",
          () => "P${random(4, 40, "r")}t",
          () => "F${random(1, 5, "a")}rt",
          () => "Th${List.generate(rn(4, 20), (_) => random(1, 4, ro(["h", "t"]))).join("")}",
          () => "B${maybe("h")}l${random(6, 26, "a")}${maybe("h")}n${maybe("h")}k",
          () => "Squ${random(1, 2, ro(["i", "e"]))}rk",
        ];

        await context.respond(MessageBuilder(
          content: List.generate(amount, (_) => ro(farts).call()).join("\n"),
        ));
      }, CommandAttributes(category: "Fun")),

      BotCommand("mock", "Fun", "Mock a message.", (ChatContext context, [GreedyString? input]) async {
        String? data = input?.data;

        if (input == null && context is MessageChatContext) {
          final reply = context.message.referencedMessage;
          data = reply?.content;
        }

        if (data == null) return context.respondWithError("No message or input found.");
        List<String> parts = [];
        bool uppercase = Random().nextInt(2) == 1;

        for (final c in data.split("")) {
          if (RegExp(r'[a-zA-Z]').hasMatch(c)) {
            parts.add(uppercase ? c.toUpperCase() : c.toLowerCase());
            uppercase = !uppercase;
          } else {
            parts.add(c);
          }
        }

        await context.respond(MessageBuilder(content: parts.join("")));
      }),

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
    ],
  );

  if (context == null) return;
  Logger.print("main", "Bot loaded!");

  context.clients.run((client) => client.updatePresence(PresenceBuilder(
    since: DateTime(1434, 7, 13, 13, 42, 58),
    status: CurrentUserStatus.online,
    activities: [
      ActivityBuilder(
        name: "Holding down the server${dev ? " (dev mode)" : ""}",
        type: ActivityType.watching,
      ),
    ],
    isAfk: false,
  )));
};

Future<List<Member>> getAllMembers(Guild guild, {int limitPer = 1000}) async {
  List<Member> result = [];

  while (true) {
    try {
      final members = await guild.members.list(limit: limitPer, after: result.lastOrNull?.id);
      Logger.print("getAllMembers", "Found ${members.length} (${result.length} existing)");

      if (members.isEmpty) break;
      result.addAll(members);
      if (members.length < limitPer) break;
    } catch (e) {
      Logger.warn("getAllMembers", "Error: $e (${result.length} existing)");
      break;
    }
  }

  return result;
}

Future<Role?> getRole(Guild guild, Snowflake id) async {
  try {
    return (await guild.roles.list()).firstWhereOrNull((y) => y.id == id);
  } catch (e) {
    Logger.warn("getRole", "${guild.id},$id: $e");
    return null;
  }
}

int getHour() {
  return DateTime.now().difference(DateTime(2025)).inHours;
}

class Calebh101BotServerSettings extends ServerSettings {
  SettingsObject<List<XPLevel>> get xpLevels => SettingsObject(this, "levels", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => XPLevel.fromJson(x)).toList());
  SettingsObject<int> get xpChannel => SettingsObject(this, "xpChannel");
  SettingsObject<bool> get pingOnLevelUp => SettingsObject(this, "pingOnLevelUp");
  SettingsObject<List<Snowflake>> get xpBanned => SettingsObject(this, "xpBanned", encodeFunction: (input) => input.map((x) => x.value).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Snowflake(x)).toList());
  SettingsObject<bool> get xpEnabled => SettingsObject(this, "xpEnabled");
  SettingsObject<Snowflake> get mathChannel => SettingsObject(this, "mathChannel", encodeFunction: (input) => input.value, decodeFunction: (input) => input is int ? Snowflake(input) : null);
  SettingsObject<Math> get currentMath => SettingsObject(this, "currentMath", encodeFunction: (input) => input.toJson(), decodeFunction: (input) => input != null ? Math.fromJson(input) : null);
  SettingsObject<DateTime> get lastMath => SettingsObject(this, "lastMath", encodeFunction: (input) => input.millisecondsSinceEpoch, decodeFunction: (input) => DateTime.fromMillisecondsSinceEpoch(input));
  SettingsObject<List<String>> get allowedMathTypes => SettingsObject(this, "allowedMathTypes", encodeFunction: (input) => input as List?, decodeFunction: (input) => RecursiveCaster.cast<List<String>>(input));
  SettingsObject<Map<int, String>> get rules => SettingsObject(this, "rules", encodeFunction: (input) => input.map((k, v) => MapEntry(k.toString(), v)), decodeFunction: (input) => input is Map ? input.map((k, v) => MapEntry(int.parse(k), v)) : null);

  Calebh101BotServerSettings(super.store, super.id);
}

class Calebh101BotUserSettings extends UserSettings {
  Calebh101BotUserSettings(super.store, super.id);
}

class Calebh101BotUserPerServerSettings extends UserPerServerSettings {
  SettingsObject<double> get xp => SettingsObject(this, "xp");
  SettingsObject<int> get lastXpHour => SettingsObject(this, "lastXpHour");
  SettingsObject<double> get xpThisHour => SettingsObject(this, "xpThisHour");
  SettingsObject<int> get mathStreak => SettingsObject(this, "mathStreak");

  Calebh101BotUserPerServerSettings(super.store, super.server, super.user);
}

Future<List<Message>> getAllMessages(TextChannel channel, {required int limit, int limitPer = 100}) async {
  List<Message> result = [];

  while (true) {
    try {
      final messages = await channel.messages.fetchMany(limit: limitPer, after: result.lastOrNull?.id);
      Logger.print("getAllMessages", "Found ${messages.length} (${result.length} existing)");

      if (messages.isEmpty) break;
      result.addAll(messages);
      if (result.length >= limit) break;
      if (messages.length < limitPer) break;
    } catch (e) {
      Logger.warn("getAllMessages", "Error: $e (${result.length} existing)");
      break;
    }
  }

  final r = result.sublist(0, min(limit, result.length));
  Logger.print("getAllMessages", "Found ${r.length} results from limit of $limit");
  return r;
}