import 'dart:math';

import 'package:calebh101_bot/commands/fun.dart';
import 'package:calebh101_bot/commands/xp.dart';
import 'package:calebh101_bot/types.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

final double maxXpPerHour = 1;
final double xpPerReaction = 0.01;
final double Function(String content) xpPerMessage = (content) => min(content.length / 1000, 0.2); // Message length of 200+ => 0.2, 20 => 0.02, 2 => 0.02

final store = KVStore("database.db");

void main(List<String> arguments) => onStart = () async {
  Modlog({
    ModLogGroup.all: (levelBelow) => {...levelBelow, "xp.add"},
    ModLogGroup.normal: (levelBelow) => {...levelBelow, "xp.levelup"},
    ModLogGroup.quiet: (levelBelow) => levelBelow,
  });

  final context = await load(
    botName: "Kyle",
    version: Version.parse("0.0.0A"),

    owner: calebh101,
    supportServer: calebh101Server,

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
      restartCommand(),
      sendMessageAs(),
      aboutCommand(store),
      fart(),

      helpCommand((x) => Calebh101BotServerSettings(store, x.id), plugin),
      listAllServerSettings((x) => Calebh101BotServerSettings(store, x.id)),
      killCommand((x) => Calebh101BotServerSettings(store, x.id)),
      echoDebugCommand((x) => Calebh101BotServerSettings(store, x.id)),
      deleteMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),
      editMyMessageCommand((x) => Calebh101BotServerSettings(store, x.id)),

      ...adminCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...modLogCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...prefixCommands((x) => Calebh101BotServerSettings(store, x.id)),
      ...ignoreCommands(store),
      ...xpCommands(store),

      BotCommand.command("stats", "See your stats, or somebody else's.", (ChatContext context, [Member? member]) async {
        member ??= context.member;
        if (member == null || context.guild == null) return context.respondWithError("No guild/member found.");
        final guild = context.guild!;
        final avatar = member.avatar ?? member.user?.avatar;

        final serverSettings = Calebh101BotServerSettings(store, guild.id);
        final settings = Calebh101BotUserPerServerSettings(store, guild.id, member.id);
        final String level = getRole(guild, Snowflake(levelFromXp(serverSettings.xpLevels.get() ?? [], getRoundedXp(settings))?.roleId ?? 0))?.toMention() ?? "Member";

        List<String> properties = [
          if (guild.ownerId == member.id) "Server Owner",
          if (isAdmin(settings: serverSettings, id: member.id)) "Bot Admin",
          if (isClaimer(settings: serverSettings, id: member.id)) "Bot Claimer",
          if (isOwner(id: member.id)) "Bot Owner",
        ];

        await context.respond(MessageBuilder(
          embeds: [
            EmbedBuilder(
              title: "Stats for ${await memberToString(member)}",
              color: (await getPrimaryColor(member)) ?? primaryBotColor,
              timestamp: DateTime.now().toUtc(),
              fields: [
                EmbedFieldBuilder(name: "XP", value: getRoundedXp(settings).toString(), isInline: true),
                EmbedFieldBuilder(name: "Level", value: level, isInline: true),
                EmbedFieldBuilder(name: "Joined On", value: "${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.longDateTime)} (${member.joinedAt.toDiscordTimestamp(DiscordTimestamp.relative)})", isInline: false),
                if (properties.isNotEmpty) EmbedFieldBuilder(name: "Properties", value: properties.join(", "), isInline: false),
              ],
              footer: isAdmin(settings: serverSettings, id: context.user.id) ? EmbedFooterBuilder(text: "Exact XP: ${settings.xp.get()}") : null,
              thumbnail: avatar != null ? EmbedThumbnailBuilder(url: avatar.url) : null,
            ),
          ],
        ));
      }, CommandAttributes(category: "User")),
    ],
  );

  if (context == null) return;
  Logger.print("main", "Bot loaded!");

  context.client.onMessageCreate.listen((event) async {
    if (isIgnored(store, event.message.author.id)) return;
    final guild = await event.guild?.get();
    final member = await event.member?.get();

    if (guild == null || !checkIsValidForXp(member)) return;
    addXp(event, guild, member!, xpPerMessage.call(event.message.content));
  });

  context.client.onMessageReactionAdd.listen((event) async {
    if (isIgnored(store, event.userId)) return;
    final guild = await event.guild?.get();
    final member = await event.member?.get();

    if (guild == null || !checkIsValidForXp(member)) return;
    addXp(event, guild, member!, xpPerReaction);
  });

  context.client.updatePresence(PresenceBuilder(
    since: DateTime(1434, 7, 13, 13, 42, 58),
    status: CurrentUserStatus.online,
    activities: [
      ActivityBuilder(
        name: "Holding down the server${dev ? " (dev mode)" : ""}",
        type: ActivityType.watching,
      ),
    ],
    isAfk: false,
  ));
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

Role? getRole(Guild guild, Snowflake id) {
  return guild.roleList.firstWhereOrNull((y) => y.id == id);
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