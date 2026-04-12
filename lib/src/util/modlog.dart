import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:localpkg/classes.dart';

typedef ModlogGroupCollection = Map<ModLogGroup, Set<String> Function(Set<String> levelBelow)>;

enum ModlogSeverity {
  verbose,
  log,
  warning,
  severe,
  error,
}

enum ModLogGroup {
  all,
  normal,
  quiet,
  off,
}

DiscordColor? modLogSeverityToColor(ModlogSeverity severity) {
  return switch (severity) {
    ModlogSeverity.verbose => DiscordColor.parseHexString("#808080"),
    ModlogSeverity.log => DiscordColor.parseHexString("#808080"),
    ModlogSeverity.warning => DiscordColor.parseHexString("#FFFF00"),
    ModlogSeverity.severe => DiscordColor.parseHexString("#FF0000"),
    ModlogSeverity.error => DiscordColor.parseHexString("#8B0000"),
  };
}

class Modlog {
  static Set<String> ignoredEvents = {"pagination"};
  static Set<String> events = {};

  Modlog._(ModlogGroupCollection collection) {
    addExtraGroup(collection);
  }

  static void addExtraGroup(ModlogGroupCollection group) {
    addExtraGroups([group]);
  }

  static void addExtraGroups(List<ModlogGroupCollection> groups) {
    extraGroupCollections.addAll(groups);
    events.addAll([...getGroup(ModLogGroup.all, addExtraGroups: false), ...groups.map((x) => getGroup(ModLogGroup.all, addExtraGroups: false, collection: x)).flatten()]);
  }

  static ModlogGroupCollection groups = {
    ModLogGroup.all: (levelBelow) => {...levelBelow, "pagination", "prefix.change"},
    ModLogGroup.normal: (levelBelow) => {...levelBelow},
    ModLogGroup.quiet: (levelBelow) => {...levelBelow, "test"},
    ModLogGroup.off: (_) => {},
  };

  static List<ModlogGroupCollection> extraGroupCollections = [];

  static Set<String> getGroup(ModLogGroup group, {ModlogGroupCollection? collection, bool addExtraGroups = true}) {
    Set<String> current = {};

    for (final level in ModLogGroup.values.reversed) {
      current = (collection ?? groups)[level]?.call(current) ?? {};
      if (level == group) break;
    }

    if (addExtraGroups) current = current.union(extraGroupCollections.map((x) => getGroup(group, collection: x, addExtraGroups: false)).flatten().toSet());
    return current.where((x) => !ignoredEvents.contains(x)).toSet();
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

      final channel = await event.client.channels.get(Snowflake(event.settings!.modlogChannel.get()!));
      if (channel is! GuildTextChannel) return "Specified channel is not a text channel.";

      await channel.sendMessage(MessageBuilder(embeds: [
        EmbedBuilder(
          title: event.title,
          description: event.description,
          fields: List.generate(event.fields.length, (i) {
            final field = event.fields.entries.elementAt(i);
            return EmbedFieldBuilder(name: field.key, value: field.value, isInline: false);
          }),
          timestamp: event.timestamp,
          footer: EmbedFooterBuilder(text: event.eventId),
          color: modLogSeverityToColor(event.severity),
        ),
      ]));

      return null;
    } catch (e) {
      Logger.warn("Modlog", "Unable to log event ${event.eventId}: $e");
      return "Unknown error.";
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
  final Map<String, String> fields;
  final ModlogSeverity severity;
  final Uri? url;
  final EmbedImageBuilder? image;
  final EmbedThumbnailBuilder? thumbail;
  DateTime? timestamp;
  List<String>? alsoTriggerOn;
  late List<String> triggers;

  ModlogEvent(this.eventId, {this.severity = ModlogSeverity.log, required this.guild, required this.settings, required this.title, this.description, this.fields = const {}, this.timestamp, this.url, this.image, this.thumbail, this.alsoTriggerOn, required this.client}) {
    timestamp ??= DateTime.now();
    triggers = [eventId, ...?alsoTriggerOn];
  }
}

List<BotCommand> modLogCommands(ServerSettings? Function(Guild guild) getSettings) => [
  BotCommand.command(
    "modlogchannel", "Set the preferred channel for mod logs. The bot must be able to send a message there.",
    (ChatContext context, [GuildTextChannel? channel]) async {
      if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
      final settings = getSettings.call(context.guild!);
      if (settings == null) return context.respondWithError("No settings found.");
      if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

      if (channel == null) {
        settings.modlogChannel.delete();
        await context.respond(MessageBuilder(content: "Modlog channel unset."));
        return;
      }

      try {
        await channel.sendMessage(MessageBuilder(content: "Modlog channel set to **this channel**!"));
      } catch (e) {
        Logger.warn("Commands.ModlogChannel", "Unable to send message in channel ${channel.id}: $e");
        return context.respondWithError("Unable to send message in channel <#${channel.id}>.");
      }

      settings.modlogChannel.set(channel.id.value);
      await context.respond(MessageBuilder(content: "Modlog channel set to <#${channel.id}>!"));
    },
    CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "modlog"),
  ),
  BotCommand.command("modlogscopes", "Select scopes to log.", (ChatContext context, [String? input]) async {
    if (Modlog.events.isEmpty) return context.respondWithError("Modlog is not enabled.\n-# No events allowed. Did you forget to call `Modlog()`?");
    if (context.guild == null || context.member == null) return context.respondWithError("No guild/member found.");
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("No settings found.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    if (input == null) {
      final current = settings.modlog.get();

      await context.respond(MessageBuilder(
        content: [
          "**${Modlog.events.length}** ${Word.fromCount(Modlog.events.length, singular: Word("scope"))} available: ${Modlog.events.map((x) => "`$x`").join(", ")}",
          if (current?.isNotEmpty ?? false) "**${current!.length}** ${Word.fromCount(current.length, singular: Word("scope"))} enabled: ${current.map((x) => "`$x`").join(", ")}",
        ].join("\n"),
      ));

      return;
    }

    final enabled = <String>[];
    final invalid = <String>[];

    final group = ModLogGroup.values.firstWhereOrNull((x) => x.name == input.trim());
    final Set<String> items = group != null ? Modlog.getGroup(group) : input.split(',').map((s) => s.trim()).where((x) => x.isNotEmpty).toSet();

    for (final x in items) {
      if (Modlog.events.contains(x)) {
        enabled.add(x);
      } else {
        invalid.add(x);
      }
    }

    settings.modlog.set(enabled);

    await context.respond(MessageBuilder(
      content: [
        "**${enabled.length}** ${Word.fromCount(enabled.length, singular: Word("scope"))} enabled: ${enabled.isNotEmpty ? enabled.map((x) => "`$x`").join(", ") : ""}",
        if (group != null) "From group: `${group.name}`",
        if (invalid.isNotEmpty) "-# **${invalid.length}** ${Word.fromCount(invalid.length, singular: Word("scope"))} are invalid: ${invalid.map((x) => "`$x`").join(", ")}",
        "-# **${Modlog.events.length}** ${Word.fromCount(Modlog.events.length, singular: Word("scope"))} available: ${Modlog.events.map((x) => "`$x`").join(", ")}",
      ].join("\n"),
    ));
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "modlog")),
  BotCommand.command("modlogtest", "Send a modlog message.", (ChatContext context, String title, String message) async {
    final settings = getSettings.call(context.guild!);
    if (settings == null) return context.respondWithError("No settings found.");
    if (await context.assurePerms(BotCommandPermissions.admin, settings) == false) return;

    final result = await Modlog.add(ModlogEvent("test",
      client: context.client,
      guild: context.guild,
      settings: settings,
      title: title,
      description: message,
      fields: {
        "Author": "<@${context.user.id}>",
      },
    ));

    if (result != null) {
      await context.respond(MessageBuilder(
        content: "Modlog message not sent. Reason:\n```$result```",
      ));
    } else {
      await context.respond(MessageBuilder(
        content: "Modlog message sent.",
      ));
    }
  }, CommandAttributes(permissionsRequired: BotCommandPermissions.admin, category: "modlog")),
];