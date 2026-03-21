import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:localpkg/functions.dart';

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  if (event.guild == null) return "!";
  final settings = getSettings.call(event.guild!);
  if (settings == null) return "!";

  final prefix = settings.prefix.get() ?? "!";
  return prefix;
};

ChatCommand prefixCommand(ServerSettings? Function(Guild guild) getSettings) => ChatCommand("prefix", "Set the bot's prefix. Defaults to !.", (ChatContext context, String prefix) {
  if (context.guild == null) return;
  final settings = getSettings.call(context.guild!);
  if (settings == null) return;
  settings.prefix.set(prefix);

  context.respond(MessageBuilder(
    content: "Prefix set to `$prefix`!",
  ));
});

ChatCommand listAllServerSettings(ServerSettings? Function(Guild guild) getSettings) => ChatCommand("allsettings", "List all settings for this server. Admin only.", (ChatContext context) {
  if (context.guild == null) return;
  final settings = getSettings.call(context.guild!);
  if (settings == null) return;
  final all = settings.getAll().entries;

  context.respond(MessageBuilder(
    content: "All settings for *${context.guild?.name}*:\n${all.map((x) => "- `${x.key}`: `${x.value}`").join("\n")}",
  ), level: ResponseLevel.private);
});

List<ChatCommand> adminRoles(ServerSettings? Function(Guild guild) getSettings) => [
  ChatCommand("addadminuser", "Add an admin user.", (ChatContext context, User user) {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;
    final admins = settings.admins.get() ?? [];

    if (admins.any((x) => x["type"] == "user" && x["id"] == user.id.toString())) {
      return context.respond(MessageBuilder(
        content: "<@${user.id}> is already an admin.",
      )).toVoid();
    }

    admins.add({"type": "user", "id": user.id.toString()});
    settings.admins.set(admins);

    context.respond(MessageBuilder(
      content: "Added <@${user.id}> as an admin!",
    ));
  }),
  ChatCommand("addadminrole", "Add a role as admin.", (ChatContext context, Role role) {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;
    final admins = settings.admins.get() ?? [];

    if (admins.any((x) => x["type"] == "role" && x["id"] == role.id.toString())) {
      return context.respond(MessageBuilder(
        content: "Role *${role.name}* is already an admin.",
      )).toVoid();
    }

    admins.add({"type": "role", "id": role.id.toString()});
    settings.admins.set(admins);

    context.respond(MessageBuilder(
      content: "Added role *${role.name}* as admin!",
    ));
  }),
  ChatCommand("removeadminuser", "Remove a user from admin.", (ChatContext context, User user) {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;

    final admins = settings.admins.get() ?? [];
    bool found = false;

    admins.removeWhere((x) {
      final y = x["type"] == "user" && x["id"] == user.id.toString();
      if (y) found = true;
      return y;
    });

    if (found) {
      settings.admins.set(admins);
    }

    context.respond(MessageBuilder(
      content: found ? "Removed <@${user.id}> from admin." : "<@${user.id}> is not currently an admin.",
    ));
  }),
  ChatCommand("removeadminrole", "Remove a role from admin.", (ChatContext context, Role role) {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;

    final admins = settings.admins.get() ?? [];
    bool found = false;

    admins.removeWhere((x) {
      final y = x["type"] == "role" && x["id"] == role.id.toString();
      if (y) found = true;
      return y;
    });

    if (found) {
      settings.admins.set(admins);
    }

    context.respond(MessageBuilder(
      content: found ? "Removed role *${role.name}* from admin." : "Role *${role.name}* is not currently admin.",
    ));
  }),
  ChatCommand("claim", "Claim yourself as king of the bot!", (ChatContext context) async {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;
    if (context.member == null) return;
    final mainAdmin = settings.mainAdmin.get();

    if (mainAdmin == null) {
      settings.mainAdmin.set(context.member!.id.toString());

      context.respond(MessageBuilder(
        content: "<@${context.member!.id}> has claimed me!",
      ));
    } else {
      final m = await context.respond(MessageBuilder(
        content: "I've already been claimed by someone else.",
      ));

      try {
        final member = (await context.guild!.members.get(Snowflake(int.parse(mainAdmin))));
        m.edit(MessageUpdateBuilder(content: "I've already been claimed by ${memberToString(member)}."));
      } catch (e) {
        Logger.warn("Commands.Claim", "User $mainAdmin not found: $e");
      }
    }
  }),
  ChatCommand("unclaim", "Step down as king of the bot. This will not be made known to others.", (ChatContext context) async {
    if (context.guild == null) return;
    final settings = getSettings.call(context.guild!);
    if (settings == null) return;
    if (context.member == null) return;
    final old = settings.mainAdmin.get();

    if (old == null) {
      context.respond(MessageBuilder(
        content: "I am unclaimed already.",
      ));
    } else {
      settings.mainAdmin.delete();
      if (context is MessageChatContext) await context.message.delete();

      final m = await context.respond(MessageBuilder(
        content: "I have been unclaimed.",
      ), level: ResponseLevel.private);

      try {
        final member = (await context.guild!.members.get(Snowflake(int.parse(old))));
        m.edit(MessageUpdateBuilder(content: "I have been unclaimed.\n-# I was claimed by: ${memberToString(member)}."));
      } catch (e) {
        Logger.warn("Commands.Unclaim", "User $old not found: $e");
      }
    }
  }),
];

final Map<String? Function(MessageCreateEvent event), num> pingPhrases = {
  (_) => "WHAT'S ALL THAT NOISE??": 50,
  (_) => "Ow!": 100,
  (_) => "Pong!": 100,
  (_) => "Hey there!": 100,
  (e) => "Hi there, <@${e.member!.id}>!": 100,
  (_) => "AGHGHGHGHGHGHGHGHGHGHGHGHGHGHGHHGHG": 5,
};