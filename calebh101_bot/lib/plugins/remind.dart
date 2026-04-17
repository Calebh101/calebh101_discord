import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:json_annotation/json_annotation.dart';

part 'remind.g.dart';

class RemindPlugin extends BotPlugin {
  RemindPlugin() : super(id: "remind", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("remind", "Reminders", "Remind you later, in DMs.", (T context, Duration wait, GreedyString name) async {
        final settings = RemindSettings(store, context.user.id);
        final reminders = settings.reminders.get() ?? [];
        final time =  DateTime.now().add(wait);

        var message = context is MessageChatContext ? context.message.id : (context is InteractionChatContext ? context.channel.lastMessageId : null);

        if (message == null) {
          try {
            final m = await context.channel.sendMessage(MessageBuilder(content: "Creating reminder...\n-# Don't delete this message."));
            message = m.id;
          } catch (e) {
            Logger.warn("Reminders", "Unable to send message: $e");
            return context.respondWithError("Unable to send message.");
          }
        }

        reminders.add(Reminder(name: name.data, time: time, id: settings.getNextReminderId(), clientId: context.client.user.id.value, sentChannelId: context.channel.id.value, sentGuildId: context.guild?.id.value, sentMessageId: message.value));
        settings.reminders.set(reminders);
        await context.respond(MessageBuilder(content: "Reminder set for ${time.toDiscordTimestamp(DiscordTimestamp.longDateTime)}! I'll remind you in DMs."));
      }, noGroup: true),
      BotCommand("remindhere", "Reminders", "Remind you later, in this channel.", (T context, Duration wait, GreedyString name) async {
        if (await context.assureGuild() == false) return;
        final serverSettings = RemindServerSettings(store, context.guild!.id);
        if (serverSettings.allowRemindHere.get() == false) return context.respondWithError("You can't schedule me to send a reminder in this server.");

        final settings = RemindSettings(store, context.user.id);
        final reminders = settings.reminders.get() ?? [];
        final time =  DateTime.now().add(wait);

        var message = context is MessageChatContext ? context.message.id : (context is InteractionChatContext ? context.channel.lastMessageId : null);

        if (message == null) {
          try {
            final m = await context.channel.sendMessage(MessageBuilder(content: "Creating reminder...\n-# Don't delete this message."));
            message = m.id;
          } catch (e) {
            Logger.warn("Reminders", "Unable to send message: $e");
            return context.respondWithError("Unable to send message.");
          }
        }

        reminders.add(Reminder(name: name.data, time: time, channelId: context.channel.id.value, id: settings.getNextReminderId(), clientId: context.client.user.id.value, sentChannelId: context.channel.id.value, sentGuildId: context.guild?.id.value, sentMessageId: message.value));
        settings.reminders.set(reminders);
        await context.respond(MessageBuilder(content: "Reminder set for ${time.toDiscordTimestamp(DiscordTimestamp.longDateTime)}! I'll remind you in ${context.channel.toMention()}."));
      }),
      BotCommand("reminders", "Reminders", "View all reminders.", (T context, [User? user]) async {
        if (user != null && await context.assureOwner() == false) return;
        user ??= context.user;

        final settings = RemindSettings(store, user.id);
        final reminders = settings.reminders.get() ?? [];
        if (reminders.isEmpty) return context.respondWithError("You don't have any reminders set!");

        await respondWithPagination(context, PaginatedEmbedBuilder(
          title: "All Reminders for ${await memberFromUserToString(user, client: context.client, guild: context.guild)}",
          pages: EmbedPage.generate(reminders.mapIndexed((i, x) => EmbedFieldBuilder(name: "${i + 1}. ${x.name}", value: "${x.time.toDiscordTimestamp(DiscordTimestamp.longDateTime)} in ${x.channelId?.toChannel() ?? "DMs"}", isInline: false)).toList()),
        ), settings: ifGuild(store, context.guild?.id, (id) => RemindServerSettings(store, id)));
      }),
      BotCommand("remreminder", "Reminders", "Delete a reminder.", (T context, int index) async {
        final settings = RemindSettings(store, context.user.id);
        final reminders = settings.reminders.get() ?? [];
        if (reminders.isEmpty || reminders.length < index || index < 1) return context.respondWithError("No reminders for index $index.");

        reminders.removeAt(index - 1);
        settings.reminders.set(reminders);
        if (reminders.isEmpty) settings.reminders.delete();
        await context.respond(MessageBuilder(content: "Removed reminder $index."));
      }),
      BotCommand("clearreminders", "Reminders", "Delete all reminders.", (T context) async {
        final settings = RemindSettings(store, context.user.id);
        final reminders = settings.reminders.get() ?? [];
        if (reminders.isEmpty) return context.respondWithError("You don't have any reminders set!");
        settings.reminders.delete();
        await context.respond(MessageBuilder(content: "Deleted ${reminders.length} reminders."));
      }),
      BotCommand("allowremindhere", "Reminders", "Set if the server should allow `remindhere`.", (T context, bool value) async {
        if (await context.assureGuild() == false) return;
        final settings = RemindServerSettings(store, context.guild!.id);
        settings.allowRemindHere.set(value);
        await context.respond(MessageBuilder(content: "Set allowremindhere to ${value.toDiscordCodeString()}."));
      }, permissionsRequired: BotCommandPermissions.admin),
    ];
  }

  @override
  Future<void> onClientLoad(BotContext context) async {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      final raw = context.store.getAllForKey(Scope.user, "reminders");
      if (raw.isEmpty) return;
      List<({Snowflake userId, Reminder reminder})> reminders = [];

      for (final x in raw.entries) {
        if (x.value is! List) continue;

        for (final r in x.value) {
          try {
            reminders.add((reminder: Reminder.fromJson(r), userId: Snowflake(int.parse(x.key))));
          } catch (e) {
            Logger.warn("Reminders", "Invalid reminder: $e");
          }
        }
      }

      if (reminders.isEmpty) return;

      for (final r in reminders) {
        if (r.reminder.time.isAfter(DateTime.now())) continue;
        final isDm = r.reminder.channelId == null;
        final settings = RemindSettings(context.store, r.userId);

        final client = context.clients.clients.entries.firstWhereOrNull((x) => x.value.user.id.value == r.reminder.clientId)?.value;
        if (client == null) return;

        final current = settings.reminders.get() ?? [];
        current.remove(r.reminder);
        settings.reminders.set(current);
        Member? member;

        if (r.reminder.sentGuildId != null) {
          try {
            final user = await client.users.get(r.userId);
            final guild = await client.guilds.get(Snowflake(r.reminder.sentGuildId!));
            member = await userToMember(user, guild: guild);
          } catch (e) {
            Logger.warn("Reminders", "Error getting member from user ID ${r.userId}: $e");
          }
        }

        final embed = EmbedBuilder(
          title: "You asked me to remind you...",
          description: r.reminder.name,
          color: await getColor(member),
          url: Uri.parse("https://discord.com/channels/${[r.reminder.sentGuildId ?? "@me", r.reminder.sentChannelId, r.reminder.sentMessageId].join("/")}"),
        );

        try {
          final channel = isDm ? await client.users.createDm(r.userId) : await client.channels.get(Snowflake(r.reminder.channelId!)) as TextChannel;
          await channel.sendMessage(MessageBuilder(embeds: [embed], content: isDm ? null : r.userId.value.toMention()));
        } catch (e) {
          Logger.warn("Reminders", "Unable to send reminder to user ${r.userId} in channel ${r.reminder.channelId}: $e");
        }
      }
    });
  }
}

class RemindSettings extends UserSettings {
  RemindSettings(super.store, super.id);

  SettingsObject<List<Reminder>> get reminders => SettingsObject(this, "reminders", encodeFunction: (input) => input.map((x) => x.toJson()).toList(), decodeFunction: (input) => (input as List?)?.map((x) => Reminder.fromJson(x)).toList());
  SettingsObject<int> get reminderId => SettingsObject(this, "reminderId");

  int getNextReminderId() {
    final current = reminderId.get() ?? 0;
    final next = current + 1;
    reminderId.set(next);
    return next;
  }
}

class RemindServerSettings extends ServerSettings {
  RemindServerSettings(super.store, super.id);

  SettingsObject<bool> get allowRemindHere => SettingsObject(this, "allowRemindHere");
}

@JsonSerializable(anyMap: true)
class Reminder {
  final String name;
  final DateTime time;
  final int? channelId;
  final int id;
  final int clientId;
  final int sentMessageId;
  final int sentChannelId;
  final int? sentGuildId;

  Reminder({required this.name, required this.time, this.channelId, required this.id, required this.clientId, required this.sentMessageId, required this.sentChannelId, required this.sentGuildId});
  factory Reminder.fromJson(Map input) => _$ReminderFromJson(input);
  Map toJson() => _$ReminderToJson(this);

  @override
  bool operator ==(Object other) {
    return other is Reminder && id == other.id;
  }

  @override
  int get hashCode => id.hashCode;
}
