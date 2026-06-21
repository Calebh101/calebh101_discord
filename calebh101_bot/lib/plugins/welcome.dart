import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class WelcomePlugin extends BotPluginLegacy {
  WelcomePlugin() : super(id: "welcome", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("welcomechannel", "Welcome", "Set or remove the channel for welcome messages.", (ChatContext context) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        final id = settings.welcomeChannel.get();
        await context.respond(MessageBuilder(content: id != null ? "Welcome channel is currently set to ${id.value.toChannel()}." : "No welcome channel set."));
      }, needsGuild: true),
      BotCommand("setwelcomechannel", "Welcome", "Set or remove the channel for welcome messages.", (ChatContext context, [GuildTextChannel? channel]) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.welcomeChannel.set(channel?.id);
        await context.respond(MessageBuilder(content: channel != null ? "Welcome channel set to ${channel.toMention()}!" : "Welcome channel removed."));
      }, permissionsRequired: BotCommandPermissions.admin, needsGuild: true),
      BotCommand("setignorebots", "Welcome", "Set if bots/system should be ignored. Defaults to true.", (ChatContext context, bool value) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.welcomeIgnoreBots.set(value);
        await context.respond(MessageBuilder(content: "Bots ${value ? "**will**" : "will **not**"} be ignored."));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),

      BotCommand("setwelcomemessage", "Welcome", "Set the welcome message.", (T context, [GreedyString? input]) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.welcomeMessage.set(input?.data);

        await context.respond(MessageBuilder(
          content: input == null ? "Welcome message unset." : "Welcome message set.\n\n**Raw:**\n$input\n\n**Processed:**\n${processWelcomeMessage(input.data, WelcomeMessageDetails(user: context.user, member: context.member, guild: await context.guild!.fetch(withCounts: true)))}",
        ));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin, extendedDescription: "You can use [[argument]] for specific properties.\nExample:\n\n> Hello, [[mention]]! Make sure to check out [[rules]]!\n\n ## Arguments\n${arguments(false).entries.map((entry) {
        return "- `[[${entry.key}]]`: ${entry.value.$1}";
      }).join("\n")}"),

      BotCommand("setgoodbyemessage", "Welcome", "Set the goodbye message.", (T context, [GreedyString? input]) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.goodbyeMessage.set(input?.data);

        await context.respond(MessageBuilder(
          content: input == null ? "Goodbye message unset." : "Goodbye message set.\n\n**Raw:**\n$input\n\n**Processed:**\n${processWelcomeMessage(input.data, WelcomeMessageDetails(goodbye: true, user: context.user, member: context.member, guild: await context.guild!.fetch(withCounts: true)))}",
        ));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin, extendedDescription: "You can use [[argument]] for specific properties.\nExample:\n\n> Goodbye, [[mention]] ([[username]])!\n\n ## Arguments\n${arguments(true).entries.map((entry) {
        return "- `[[${entry.key}]]`: ${entry.value.$1}";
      }).join("\n")}"),

      BotCommand("welcomemessage", "Welcome", "Get the current welcome/goodbye messages.", (T context) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        final channelId = settings.welcomeChannel.get();
        final ignoreBots = settings.welcomeIgnoreBots.get();

        final welcome = settings.welcomeMessage.get();
        final goodbye = settings.goodbyeMessage.get();

        await context.respond(MessageBuilder(
          content: "Welcome channel: ${channelId?.value.toChannel() ?? "**Not set**"}\nIgnore bots: **$ignoreBots**\n\n## Welcome Message\n${welcome != null ? "**Raw:**\n$welcome\n\n**Processed:**\n${processWelcomeMessage(welcome, WelcomeMessageDetails(user: context.user, member: context.member, guild: await context.guild!.fetch(withCounts: true)))}" : "Not set."}\n\n## Goodbye Message\n${goodbye != null ? "**Raw:**\n$goodbye\n\n**Processed:**\n${processWelcomeMessage(goodbye, WelcomeMessageDetails(goodbye: true, user: context.user, member: context.member, guild: context.guild!))}" : "Not set."}",
        ));
      }, needsGuild: true, aliases: ["goodbyemessage"]),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        final settings = WelcomeServerSettings(store, event.guildId);
        final channelId = settings.welcomeChannel.get();
        final text = settings.welcomeMessage.get();

        if (text == null) return;

        if (settings.welcomeIgnoreBots.get() != false) {
          final user = await client.users.get(event.member.id);
          if (user.isBot || user.isSystem) return;
        }

        if (channelId == null) return;
        late GuildTextChannel channel;

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Welcome", "Unable to get channel $channelId: $e");
          return;
        }

        try {
          await channel.sendMessage(MessageBuilder(content: processWelcomeMessage(text, WelcomeMessageDetails(user: await client.users.get(event.member.id), member: event.member, guild: await event.guild.fetch(withCounts: true)))));
        } catch (e) {
          Logger.warn("Welcome", "Unable to send message in channel $channelId: $e");
          return;
        }
      });

      client.onGuildMemberRemove.listen((event) async {
        final settings = WelcomeServerSettings(store, event.guildId);
        final channelId = settings.welcomeChannel.get();
        final text = settings.goodbyeMessage.get();

        if (settings.welcomeIgnoreBots.get() != false) {
          if (event.user.isBot || event.user.isSystem) return;
        }

        if (channelId == null || text == null) return;
        late GuildTextChannel channel;

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Welcome", "Unable to get channel $channelId: $e");
          return;
        }

        try {
          await channel.sendMessage(MessageBuilder(content: processWelcomeMessage(text, WelcomeMessageDetails(goodbye: true, user: event.user, member: event.removedMember, guild: await event.guild.fetch(withCounts: true)))));
        } catch (e) {
          Logger.warn("Welcome", "Unable to send message in channel $channelId: $e");
          return;
        }
      });
    });
  }
}

final Map<String, (String description, dynamic Function(WelcomeMessageDetails details) callback)> Function(bool goodbye) arguments = (goodbye) => {
  "userid": ("The user's raw ID, as a number.", (details) => details.user.id),
  "username": ("The username of the user.", (details) => details.user.username),
  "nickname": ("The user's per-server nickname, global nickname, or username, whichever is available first.", (details) => details.member?.nick ?? details.user.globalName ?? details.user.username),
  "mention": ("A mention (`<@id>`) of the user.", (details) => details.user.mention),
  "rules": ("The rules channel as a mention (`<#id>`). This is set from the guild's rules channel in the server settings. If this is not there, you will see `null`.", (details) => details.guild.rulesChannelId?.value.toChannel()),
  if (!goodbye) "membercount": ("The amount of members in the guild when the user joins. This is not available in goodbye messages.", (details) => details.guild.approximateMemberCount),
};

class WelcomeMessageDetails {
  final bool goodbye;
  final User user;
  final Member? member;
  final Guild guild;

  const WelcomeMessageDetails({this.goodbye = false, required this.user, required this.member, required this.guild});
}

String processWelcomeMessage(String input, WelcomeMessageDetails details) {
  for (final property in arguments(details.goodbye).entries) {
    input = input.replaceAll("[[${property.key}]]", property.value.$2.call(details).toString());
  }

  return input;
}

class WelcomeServerSettings extends Calebh101BotServerSettings {
  WelcomeServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get welcomeChannel => SettingsObject.snowflake(this, "welcome");
  SettingsObjectNotNull<bool> get welcomeIgnoreBots => SettingsObjectNotNull(this, "welcomeIgnoreBots", defaultFunction: () => true);

  SettingsObject<String> get welcomeMessage => SettingsObject(this, "welcomeMessage");
  SettingsObject<String> get goodbyeMessage => SettingsObject(this, "goodbyeMessage");
}