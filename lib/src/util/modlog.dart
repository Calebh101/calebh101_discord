import 'dart:convert';
import 'dart:typed_data';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

typedef ModlogGroupCollection = Map<ModlogGroup, Set<String> Function(Set<String> levelBelow)>;
typedef Severity = ModlogSeverity;

extension GetColor on Severity {
  DiscordColor get color => modLogSeverityToColor(this);
}

enum ModlogSeverity {
  verbose,
  log,
  warning,
  severe,
  good,
  blue,
  purple,
}

enum ModlogGroup {
  all,
  normal,
  quiet,
  off,
}

DiscordColor modLogSeverityToColor(ModlogSeverity severity) {
  return switch (severity) {
    ModlogSeverity.verbose => DiscordColor.parseHexString("#808080"),
    ModlogSeverity.log => DiscordColor.parseHexString("#808080"),
    ModlogSeverity.good => DiscordColor.parseHexString("#90EE90"),
    ModlogSeverity.warning => DiscordColor.parseHexString("#f1c40f"),
    ModlogSeverity.severe => DiscordColor.parseHexString("#e74c3c"),
    ModlogSeverity.blue => DiscordColor.parseHexString("#3498db"),
    ModlogSeverity.purple => DiscordColor.parseHexString("#9b59b6"),
  };
}

class Modlog {
  static Set<String> ignoredEvents = {"pagination"};
  static Set<String> events = {};
  static List<ModlogEvent> buffer = [];

  Modlog._(ModlogGroupCollection collection) {
    addExtraGroup(collection);
  }

  static void addExtraGroup(ModlogGroupCollection group) {
    addExtraGroups([group]);
  }

  static void addIgnored(Set<String> events) {
    ignoredEvents.addAll(events);
  }

  static void addExtraGroups(List<ModlogGroupCollection> groups) {
    extraGroupCollections.addAll(groups);
    events.addAll([...getGroup(ModlogGroup.all, addExtraGroups: false), ...groups.map((x) => getGroup(ModlogGroup.all, addExtraGroups: false, collection: x)).flatten()]);
  }

  static ModlogGroupCollection groups = {
    ModlogGroup.all: (levelBelow) => {...levelBelow, "pagination", "prefix.change"},
    ModlogGroup.normal: (levelBelow) => {...levelBelow},
    ModlogGroup.quiet: (levelBelow) => {...levelBelow, "test"},
    ModlogGroup.off: (_) => {},
  };

  static List<ModlogGroupCollection> extraGroupCollections = [];

  static Set<String> getGroup(ModlogGroup group, {ModlogGroupCollection? collection, bool addExtraGroups = true}) {
    Set<String> current = {};

    for (final level in ModlogGroup.values.reversed) {
      current = (collection ?? groups)[level]?.call(current) ?? {};
      if (level == group) break;
    }

    if (addExtraGroups) current = current.union(extraGroupCollections.map((x) => getGroup(group, collection: x, addExtraGroups: false)).flatten().toSet());
    return current.where((x) => !ignoredEvents.contains(x)).toSet();
  }

  static String? addBuffered(ModlogEvent event) {
    if (ignoredEvents.contains(event.eventId)) return "Event is ignored.";
    if (events.isEmpty) return "Not set up.";
    if (!events.contains(event.eventId)) throw Exception("Invalid event ID: ${event.eventId}");
    if (event.guild == null) return "No guild found.";
    if (event.settings?.modlogChannel.get() == null) return "No modlog channel set.";

    final enabledScopes = event.settings?.modlog.get();
    if (enabledScopes != null && !enabledScopes.any((x) => event.triggers.contains(x))) return "Event not in enabled scopes.";

    buffer.add(event);
    return null;
  }

  static Future<String?> send({required String id, required List<String> triggers, required NyxxGateway client, required ServerSettings? settings, required MessageBuilder message}) async {
    try {
      if (ignoredEvents.contains(id)) return "Event is ignored.";
      if (events.isEmpty) return "Not set up.";
      if (!events.contains(id)) throw Exception("Invalid event ID: $id");

      final channelId = settings?.modlogChannel.get();
      if (channelId == null) return "No modlog channel set.";

      final enabledScopes = settings?.modlog.get();
      if (enabledScopes != null && !enabledScopes.any((x) => triggers.contains(x))) return "Event not in enabled scopes.";

      final channel = await client.channels.get(Snowflake(channelId));
      if (channel is! GuildTextChannel) return "Specified channel is not a text channel.";

      await channel.sendMessage(message);
      return null;
    } catch (e) {
      Logger.warn("Modlog", "Unable to send message $id: $e");
      return "Unknown error.";
    }
  }

  static Future<String?> add(ModlogEvent event) async {
    try {
      if (ignoredEvents.contains(event.eventId)) return "Event is ignored.";
      if (events.isEmpty) return "Not set up.";
      if (!events.contains(event.eventId)) throw Exception("Invalid event ID: ${event.eventId}");
      if (event.guild == null) return "No guild found.";
      if (event.settings?.modlogChannel.get() == null) return "No modlog channel set.";

      final enabledScopes = event.settings?.modlog.get();
      if (enabledScopes != null && !enabledScopes.any((x) => event.triggers.contains(x))) return "Event not in enabled scopes.";

      for (int i = 0; i < (event.fields?.length ?? 0); i++) {
        final field = event.fields?.entries.elementAtOrNull(i);
        if (field == null) continue;

        if (field.value.length > 1024) {
          final value = field.value;
          final file = "field-${field.key}-${value.length}.txt";
          event.fields![field.key] = file.toDiscordCodeBlock();

          event.attachments ??= {};
          event.attachments![file] = utf8.encode(value);
        }
      }

      final message = MessageBuilder(
        embeds: [
          event.toEmbed(),
        ],
        attachments: (event.attachments ?? {}).entries.map((x) {
          return AttachmentBuilder(data: x.value, fileName: x.key);
        }).toList(),
      );

      return await send(id: event.eventId, triggers: event.triggers, client: event.client, settings: event.settings, message: message);
    } catch (e) {
      Logger.warn("Modlog", "Unable to log event ${event.eventId}: $e");
      return "Unknown error.";
    }
  }

  static Future<String?> flush() async {
    try {
      if (buffer.isEmpty) return "No events.";
      final clients = buffer.mapToList((x) => x.client);

      final uniqueClients = {
        for (final client in clients) client.user.id: client,
      }.values;

      for (final client in uniqueClients) {
        final channelIds = buffer.mapToList((x) => x.settings?.modlogChannel.get()).whereType<int>().toSet();

        for (final id in channelIds) {
          final channel = await client.channels.get(.new(id));

          if (channel is! GuildTextChannel) {
            Logger.print("Modlog", "Client ${client.user.id}, channel ${channel.id}: Specified channel is not a text channel.");
            continue;
          }

          final all = buffer.where((x) => x.client.user.id == client.user.id && x.settings?.modlogChannel.get() == id).toList();

          for (int i = 0; i < (all.length / 10).ceil(); i++) {
            final start = i * 10;
            final events = all.sublist(start, start + 10 >= all.length ? null : start + 10);

            final message = MessageBuilder(
              embeds: events.mapToList((x) => x.toEmbed()),
              attachments: events.mapToList((event) {
                return (event.attachments ?? {}).entries.mapToList((x) {
                  return AttachmentBuilder(data: x.value, fileName: x.key);
                });
              }).flattenedToList,
            );

            await channel.sendMessage(message);
          }
        }
      }

      return null;
    } catch (e) {
      Logger.warn("Modlog", "Unable to log buffer of ${buffer.length}: $e");
      return "Unknown error.";
    } finally {
      buffer.clear();
    }
  }
}

class ModlogEvent {
  final NyxxGateway client;
  final Guild? guild;
  final ServerSettings? settings;
  final String eventId;
  final String title;
  final String? description;
  Map<String, String>? fields;
  final ModlogSeverity severity;
  final Uri? url;
  final EmbedImageBuilder? image;
  final EmbedThumbnailBuilder? thumbnail;
  DateTime? timestamp;
  List<String>? alsoTriggerOn;
  late List<String> triggers;
  Map<String, Uint8List>? attachments;

  ModlogEvent(this.eventId, {required this.severity, required this.guild, required this.settings, required this.title, this.description, this.fields, this.timestamp, this.url, this.image, this.thumbnail, this.alsoTriggerOn, required this.client, this.attachments}) {
    timestamp ??= DateTime.now();
    triggers = [eventId, ...?alsoTriggerOn];
  }

  ModlogEvent.fromContext(this.eventId, {required this.severity, required ChatContext context, required this.settings, required this.title, this.description, this.fields, this.timestamp, this.url, this.image, this.thumbnail, this.alsoTriggerOn, this.attachments}) : client = context.client, guild = context.guild;

  EmbedBuilder toEmbed() {
    return EmbedBuilder(
      title: title,
      description: description,
      fields: List.generate(fields?.length ?? 0, (i) {
        final field = fields!.entries.elementAt(i);
        return EmbedFieldBuilder(name: field.key, value: field.value, isInline: false);
      }),
      timestamp: timestamp?.toUtc(),
      footer: EmbedFooterBuilder(text: eventId),
      color: modLogSeverityToColor(severity),
    );
  }
}
