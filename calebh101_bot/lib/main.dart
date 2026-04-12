import 'dart:math';

import 'package:calebh101_bot/plugins/math.dart';
import 'package:calebh101_bot/plugins/xp.dart';
import 'package:calebh101_bot/types.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

final double maxXpPerHour = 1;
final double xpPerReaction = 0.01;
final double Function(String content) xpPerMessage = (content) => min(content.length / 1000, 0.2); // Message length of 200+ => 0.2, 20 => 0.02, 2 => 0.02

final store = KVStore("database.db");
final tokens = BotTokenStore("settings.json");
final plugins = PluginStore();

void main(List<String> arguments) => onStart = () async {
  Modlog.addExtraGroup({
    ModLogGroup.all: (levelBelow) => {...levelBelow, "xp.add"},
    ModLogGroup.normal: (levelBelow) => {...levelBelow, "xp.levelup"},
    ModLogGroup.quiet: (levelBelow) => levelBelow,
  });

  await plugins.registerAll([
    AdminPlugin(),
    SelfReactPlugin(),
    BotManagePlugin(),
    HelpPlugin(),
    XPPlugin(),
    MathPlugin(),
  ]);

  final context = await load(
    botName: "Kyle",
    version: Version.parse("0.0.0A"),

    owner: calebh101,
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

    commands: (plugin) => [
      BotCommand.converter((plugin) => plugin.getConverter(RuntimeType<GuildTextChannel>(), logWarn: false)),
      defaultCheck(store),

      pingCommand(),
      messageMe(),
      sendMessageAs(),
      aboutCommand(store),
      statusCommand(),

      listAllServerSettings((x) => Calebh101BotServerSettings(store, x.id)),
      deleteMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),
      editMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),

      ...modLogCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...prefixCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...ignoreCommands(store),

      BotCommand.command("fart", "Fart.", (ChatContext context, [int amount = 1]) async {
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
          () => "B${maybe("h")}l${random(6, 24, "a")}${maybe("h")}n${maybe("h")}k",
          () => "Squ${random(1, 2, ro(["i", "e"]))}rk",
        ];

        await context.respond(MessageBuilder(
          content: List.generate(amount, (_) => ro(farts).call()).join("\n"),
        ));
      }, CommandAttributes(category: "Fun"))
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
  return (await guild.roles.list()).firstWhereOrNull((y) => y.id == id);
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
  SettingsObject<Math> get currentMath => SettingsObject(this, "currentMath", encodeFunction: (input) => input.toJson(), decodeFunction: (input) => Math.fromJson(input));

  Calebh101BotServerSettings(super.store, super.id);
}

class Calebh101BotUserSettings extends UserSettings {
  Calebh101BotUserSettings(super.store, super.id);
}

class Calebh101BotUserPerServerSettings extends UserPerServerSettings {
  SettingsObject<double> get xp => SettingsObject(this, "xp");
  SettingsObject<int> get lastXpHour => SettingsObject(this, "lastXpHour");
  SettingsObject<double> get xpThisHour => SettingsObject(this, "xpThisHour");

  Calebh101BotUserPerServerSettings(super.store, super.server, super.user);
}