import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';

final Map<Snowflake, UserStatus?> cache = {};

class StatusPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "status", version: Version.parse("1.0.0A"), description: "Tracking user statuses.");

  bool isExempt(KVStore store, Snowflake id) {
    return LastSeenUserSettings(store, id).exemptFromTracking.get();
  }

  @override
  FutureOr<void> onClientLoad(BotContext context) {
    final store = context.store;

    context.clients.run((client) {
      client.onPresenceUpdate.listen((data) {
        final id = data.user?.id;
        if (id == null) return;

        if (isIgnored(store, id) || isExempt(store, id)) return;
        cache[id] = data.status;
        final settings = LastSeenUserSettings(store, id);

        if (data.status != .offline) {
          settings.lastOnline.set(.now());
        }
      });

      client.onMessageCreate.listen((data) async {
        if (data.guildId == null) return;
        if (data.message.author is! User) return;

        final member = await data.member?.get();
        final user = member?.user ?? data.message.author as User;
        final id = user.id;

        if (isIgnored(store, id) || isExempt(store, id)) return;
        final settings = LastSeenUserPerServerSettings(store, data.guildId!, id);
        settings.lastMessage.set(.now());
      });
    });
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("lastseen", "User", "Get when a user was last seen.", (T context, Member member) async {
        if (isIgnored(store, member.id)) return context.respondWithError("This user is unavailable.");
        if (isExempt(store, member.id)) return context.respondWithError("This user has chosen not to be tracked.");

        final user = LastSeenUserSettings(store, member.id);
        final ups = LastSeenUserPerServerSettings(store, context.guildId!, member.id);

        if (member.status != null && member.status != .offline) {
          return context.respondWithError("${await memberToString(member, client: context.client)} is here right now!");
        }

        final Map<String, DateTime> data = {
          "Last online": ?user.lastOnline.get(),
          "Last message here": ?ups.lastMessage.get(),
        };

        if (data.isEmpty) {
          return context.respondWithError("This user has no data available.");
        }

        await context.respond(MessageBuilder(content: data.mapTo((key, date) {
          return "- **$key**: ${date.toDiscordTimestamp(DiscordTimestamp.shortDateTime)}";
        }).join("\n")));
      }, needsGuild: true, aliases: ["lastonline"]),

      BotCommand("lastseenforce", "User", "Get when a user was last seen.", (T context, Member member) async {
        final user = LastSeenUserSettings(store, member.id);
        final ups = LastSeenUserPerServerSettings(store, context.guildId!, member.id);

        final Map<String, DateTime?> data = {
          "Last online": user.lastOnline.get(),
          "Last message here": ups.lastMessage.get(),
        };

        await context.respond(MessageBuilder(content: data.mapTo((key, date) {
          return "- **$key**: ${date?.toDiscordTimestamp(DiscordTimestamp.shortDateTime) ?? "Not available"}";
        }).join("\n")));
      }, needsGuild: true, permissionsRequired: .owner),

      BotCommand("allowtracking", "User", "Set if you allow the bot to track when you were last online, and when you last sent a message in each server.", (T context, bool input) async {
        final settings = LastSeenUserSettings(store, context.userId);
        settings.exemptFromTracking.set(!input);

        await context.respond(MessageBuilder(content: "Tracking **${input ? "enabled" : "disabled"}**."));
      }, extendedDescription: "The bot will only track **two** things:\n- When your status was not offline last\n- When you last sent a message **per server**\n\nNotes:\n- Invisible still counts as offline.\n- Users will not be able to track your messages across servers; the bot only tracks your last message in each server."),
    ];
  }
}

class LastSeenUserSettings extends UserSettings {
  LastSeenUserSettings(super.store, super.id);

  SettingsObject<DateTime> get lastOnline => .dateTime(this, "lastOnline");
  SettingsObjectNotNull<bool> get exemptFromTracking => SettingsObjectNotNull(this, "exemptFromTracking", defaultFunction: () => false);
}

class LastSeenUserPerServerSettings extends UserPerServerSettings {
  LastSeenUserPerServerSettings(super.store, super.server, super.user);

  SettingsObject<DateTime> get lastMessage => .dateTime(this, "lastMessage");
}

extension GetStatusUser on PartialUser {
  UserStatus? get status => cache[this.id];
}

extension GetStatusMember on PartialMember {
  UserStatus? get status => cache[this.id];
}