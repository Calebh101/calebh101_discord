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
      BotCommand("setgoodbye", "Welcome", "Set if messages should be sent if users leave. Defaults to true.", (ChatContext context, bool value) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.goodbye.set(value);
        await context.respond(MessageBuilder(content: "Goodbye messages ${value ? "**will**" : "will **not**"} be sent for users who leave."));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setignorebots", "Welcome", "Set if bots/system should be ignored. Defaults to true.", (ChatContext context, bool value) async {
        final settings = WelcomeServerSettings(store, context.guild!.id);
        settings.welcomeIgnoreBots.set(value);
        await context.respond(MessageBuilder(content: "Bots ${value ? "**will**" : "will **not**"} be ignored."));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    context.clients.run((client) {
      client.onGuildMemberAdd.listen((event) async {
        final settings = WelcomeServerSettings(store, event.guildId);
        final channelId = settings.welcomeChannel.get();

        if (settings.welcomeIgnoreBots.get() != false) {
          final user = await client.users.get(event.member.id);
          if (user.isBot || user.isSystem) return;
        }

        if (channelId == null) return;
        late GuildTextChannel channel;
        final guild = await event.guild.get();

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Welcome", "Unable to get channel $channelId: $e");
          return;
        }

        try {
          await channel.sendMessage(MessageBuilder(content: [
            "Hey there, ${event.member.toMention()}! We're glad you came!",
            if (guild.rulesChannelId != null) "Please take a minute to read the rules in ${guild.rulesChannelId?.value.toChannel()}.",
          ].join("\n")));
        } catch (e) {
          Logger.warn("Welcome", "Unable to send message in channel $channelId: $e");
          return;
        }
      });

      client.onGuildMemberRemove.listen((event) async {
        final settings = WelcomeServerSettings(store, event.guildId);
        final channelId = settings.welcomeChannel.get();

        if (settings.welcomeIgnoreBots.get() != false) {
          if (event.user.isBot || event.user.isSystem) return;
        }

        if (channelId == null || settings.goodbye.get() == false) return;
        late GuildTextChannel channel;

        final guild = await event.guild.get();
        final member = guild.members.cache[event.user.id];

        try {
          channel = await client.channels.get(channelId) as GuildTextChannel;
        } catch (e) {
          Logger.warn("Welcome", "Unable to get channel $channelId: $e");
          return;
        }

        try {
          await channel.sendMessage(MessageBuilder(content: "Goodbye, ${await userOrMemberToString(member, event.user, client: client)}!"));
        } catch (e) {
          Logger.warn("Welcome", "Unable to send message in channel $channelId: $e");
          return;
        }
      });
    });
  }
}

class WelcomeServerSettings extends Calebh101BotServerSettings {
  WelcomeServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get welcomeChannel => SettingsObject.snowflake(this, "welcome");
  SettingsObject<bool> get goodbye => SettingsObject(this, "goodbye");
  SettingsObject<bool> get welcomeIgnoreBots => SettingsObject(this, "welcomeIgnoreBots");
}