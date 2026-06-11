import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/recursive_caster.g.dart';
import 'package:collection/collection.dart';

class TagsPlugin extends BotPluginLegacy {
  TagsPlugin() : super(id: "tags", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<ModlogGroupCollection>> modlogGroups() {
    return [
      {
        ModlogGroup.all: (levelBelow) => {...levelBelow, "tag.set", "tag.delete"},
        ModlogGroup.normal: (levelBelow) => {...levelBelow},
        ModlogGroup.quiet: (levelBelow) => {...levelBelow},
        ModlogGroup.off: (_) => {},
      },
    ];
  }

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("settag", "Tags", "Add/edit a server-wide tag.", (T context, String name, GreedyString content) async {
        if (await context.assureGuild() == false) return;
        final settings = TagsServerSettings(store, context.guild!.id);
        final tags = settings.tags.get() ?? {};
        final exists = tags.containsKey(name);

        tags[name] = content.data;
        settings.tags.set(tags);
        await context.respond(MessageBuilder(content: "${exists ? "Edited" : "Added"} server tag `$name`."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("setptag", "Tags", "Add/edit a personal tag.", (T context, String name, GreedyString content) async {
        final settings = TagsServerPersonalSettings(store, context.guild!.id);
        final tags = settings.tags.get() ?? {};
        final exists = tags.containsKey(name);

        tags[name] = content.data;
        settings.tags.set(tags);
        await context.respond(MessageBuilder(content: "${exists ? "Edited" : "Added"} personal tag `$name` for ${await userOrMemberToString(context.member, context.user, client: context.client)}."));
      }),
      BotCommand("remtag", "Tags", "Delete a server-wide tag.", (T context, String name) async {
        if (await context.assureGuild() == false) return;
        final settings = TagsServerSettings(store, context.guild!.id);
        final tags = settings.tags.get() ?? {};
        final exists = tags.containsKey(name);

        if (exists) tags.remove(name);
        settings.tags.set(tags);
        await context.respond(MessageBuilder(content: "${exists ? "Deleted" : "Couldn't find"} server tag `$name`."));
      }, permissionsRequired: BotCommandPermissions.admin),
      BotCommand("remptag", "Tags", "Delete a personal tag.", (T context, String name) async {
        final settings = TagsServerPersonalSettings(store, context.guild!.id);
        final tags = settings.tags.get() ?? {};
        final exists = tags.containsKey(name);

        if (exists) tags.remove(name);
        settings.tags.set(tags);
        await context.respond(MessageBuilder(content: "${exists ? "Deleted" : "Couldn't find"} personal tag `$name` for ${await userOrMemberToString(context.member, context.user, client: context.client)}."));
      }),
      BotCommand("tag", "Tags", "Print a tag, from either the server's tags or your personal tags.", (T context, GreedyString name) async {
        final serverSettings = ifGuild(store, context.guild?.id, (id) => TagsServerSettings(store, id));
        final userSettings = TagsServerPersonalSettings(store, context.user.id);

        final server = serverSettings?.tags.get();
        final user = userSettings.tags.get() ?? {};

        final serverTag = server?.entries.firstWhereOrNull((x) => x.key.trim() == name.data.trim());
        final userTag = user.entries.firstWhereOrNull((x) => x.key.trim() == name.data.trim());

        final tag = userTag ?? serverTag;
        final isServer = userTag == null && serverTag != null;

        if (tag == null) {
          return context.respondWithError("No tag found for name `$name`.\nUse `tagsearch $name` to query tags.");
        }

        await context.respond(MessageBuilder(content: [
          isServer ? "**${tag.key.trim()}**:" : "${context.member!.nick ?? context.user.globalName ?? context.user.username}'s **${tag.key.trim()}** tag:",
          tag.value,
        ].join("\n\n")));
      }),
      BotCommand("stag", "Tags", "Print a tag, from the server's tags.", (T context, GreedyString name) async {
        final serverSettings = ifGuild(store, context.guild?.id, (id) => TagsServerSettings(store, id));
        final server = serverSettings?.tags.get();
        final tag = server?.entries.firstWhereOrNull((x) => x.key.trim() == name.data.trim());

        if (tag == null) {
          return context.respondWithError("No tag found for name `$name`.\nUse `tagsearch $name` to query tags.");
        }

        await context.respond(MessageBuilder(content: [
          "**${tag.key.trim()}**:",
          tag.value,
        ].join("\n\n")));
      }),
      BotCommand("ptag", "Tags", "Print a tag, from your personal tags.", (T context, GreedyString name) async {
        final userSettings = TagsServerPersonalSettings(store, context.user.id);
        final user = userSettings.tags.get() ?? {};
        final tag = user.entries.firstWhereOrNull((x) => x.key.trim() == name.data.trim());

        if (tag == null) {
          return context.respondWithError("No tag found for name `$name`.\nUse `tagsearch $name` to query tags.");
        }

        await context.respond(MessageBuilder(content: [
          "${context.member!.nick ?? context.user.globalName ?? context.user.username}'s **${tag.key.trim()}** tag:",
          tag.value,
        ].join("\n\n")));
      }),
      BotCommand("tagsearch", "Tags", "Search for a tag.", (T context, String query) async {
        final serverSettings = ifGuild(store, context.guild?.id, (id) => TagsServerSettings(store, id));
        final userSettings = TagsServerPersonalSettings(store, context.user.id);

        final server = serverSettings?.tags.get()?.entries.map((x) => (type: 0, tag: x)).toList() ?? [];
        final user = userSettings.tags.get()?.entries.map((x) => (type: 1, tag: x)).toList() ?? [];
        final all = user + server;

        final List<({MapEntry<String, String> tag, int type, double score})> ranking = all.map((x) => (tag: x.tag, score: fuzzyScore(query, x.tag.key), type: x.type)).sorted((a, b) => b.score.compareTo(a.score));
        final results = ranking.sublist(0, min(6, ranking.length));
        if (results.isEmpty) return context.respondWithError("No results found.");

        await context.respond(MessageBuilder(embeds: [
          EmbedBuilder(
            title: "${results.length} Results",
            description: query.toDiscordCodeBlock(),
            color: await getColor(context.member),
            footer: EmbedFooterBuilder(text: "${ranking.length} Total"),
            fields: results.map((x) {
              final d = x.tag.value;
              final ds = d.substring(0, min(d.length, 40));

              return EmbedFieldBuilder(
                name: "${x.tag.key} (${x.type == 0 ? "server" : "personal"})",
                value: "$ds${ds.length == d.length ? "" : "..."}".toDiscordCodeBlock(),
                isInline: false,
              );
            }).toList(),
          ),
        ]));
      }),
      BotCommand("topicfromtag", "Tags", "Set a channel's topic from a tag.", (T context, String name, [GuildTextChannel? target]) async {
        final channel = target ?? context.channel;
        if (channel is! GuildTextChannel) return context.respondWithError("No channel found.\n-# Got: ${channel.runtimeType.toDiscordCodeString()}, expected: ${RuntimeType<GuildTextChannel>().internalType.toDiscordCodeString()}");
        if (await context.assureGuild() == false) return;
        final serverSettings = ifGuild(store, context.guild?.id, (id) => TagsServerSettings(store, id));
        final userSettings = TagsServerPersonalSettings(store, context.user.id);

        final server = serverSettings?.tags.get();
        final user = userSettings.tags.get() ?? {};

        final serverTag = server?.entries.firstWhereOrNull((x) => x.key.trim() == name.trim());
        final userTag = user.entries.firstWhereOrNull((x) => x.key.trim() == name.trim());

        final tag = userTag ?? serverTag;
        final isServer = userTag == null && serverTag != null;

        if (tag == null) {
          return context.respondWithError("No tag found for name `$name`.\nUse `tagsearch $name` to query tags.");
        }

        await channel.update(GuildTextChannelUpdateBuilder(topic: tag.value.trim()));
        await context.respond(MessageBuilder(content: "Set topic of ${channel.toMention()} to ${isServer ? "server" : "personal"} tag ${tag.key.toDiscordCodeString()}."));
      }, permissionsRequired: .admin),
    ];
  }
}

class TagsServerSettings extends ServerSettings {
  TagsServerSettings(super.store, super.id);

  SettingsObject<Map<String, String>> get tags => SettingsObject(this, "tags", encodeFunction: (input) => input as Map, decodeFunction: (input) => input != null ? RecursiveCaster.cast<Map<String, String>>(input) : null);
}

class TagsServerPersonalSettings extends UserSettings {
  TagsServerPersonalSettings(super.store, super.id);

  SettingsObject<Map<String, String>> get tags => SettingsObject(this, "tags", encodeFunction: (input) => input as Map, decodeFunction: (input) => input != null ? RecursiveCaster.cast<Map<String, String>>(input) : null);
}