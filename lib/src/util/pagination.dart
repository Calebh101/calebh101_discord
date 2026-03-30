import 'dart:async';

import 'package:async/async.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';

class EmbedPage {
  final List<EmbedFieldBuilder> fields;
  const EmbedPage({required this.fields});

  static List<EmbedPage> generate(List<EmbedFieldBuilder> fields, {int maxLinesPerPage = 15}) {
    List<EmbedPage> pages = [];
    List<EmbedFieldBuilder> currentPage = [];
    int currentPageLength = 0;

    for (int i = 0; i < fields.length; i++) {
      final f = fields[i];
      currentPage.add(f);
      currentPageLength += f.value.split("\n").length + 1;

      if (currentPageLength >= maxLinesPerPage) {
        pages.add(EmbedPage(fields: List.of(currentPage)));
        currentPage = [];
        currentPageLength = 0;
      }
    }

    if (currentPage.isNotEmpty) pages.add(EmbedPage(fields: List.of(currentPage)));
    return pages;
  }
}

class ElementBasedEmbedFooterBuilder {
  List<String>? elements;
  Uri? iconUrl;

  ElementBasedEmbedFooterBuilder({this.elements, this.iconUrl});
}

class PaginatedEmbedBuilder {
  String? title;
  String? description;
  Uri? url;
  DateTime? timestamp;
  DiscordColor? color;
  ElementBasedEmbedFooterBuilder? footer;
  EmbedImageBuilder? image;
  EmbedThumbnailBuilder? thumbnail;
  EmbedAuthorBuilder? author;
  List<EmbedPage> pages;

  PaginatedEmbedBuilder({
    this.title,
    this.description,
    this.url,
    this.timestamp,
    this.color,
    this.footer,
    this.image,
    this.thumbnail,
    this.author,
    required this.pages,
  });

  EmbedBuilder build(int page, {List<String> extraFooterElements = const []}) {
    return EmbedBuilder(
      title: title,
      description: description,
      url: url,
      timestamp: timestamp,
      color: color,
      footer: EmbedFooterBuilder(text: [...?footer?.elements, if (pages.length > 1) "Page ${page + 1}/${pages.length}", ...extraFooterElements].join(" - "), iconUrl: footer?.iconUrl),
      image: image,
      thumbnail: thumbnail,
      author: author,
      fields: pages[page].fields,
    );
  }

  EmbedBuilder buildFull() {
    return EmbedBuilder(
      title: title,
      description: description,
      url: url,
      timestamp: timestamp,
      color: color,
      footer: EmbedFooterBuilder(text: [...?footer?.elements].join(" - "), iconUrl: footer?.iconUrl),
      image: image,
      thumbnail: thumbnail,
      author: author,
      fields: flatten(pages.map((x) => x.fields).toList()),
    );
  }
}

Future<bool> dumpPagination(PaginatedEmbedBuilder embed, TextChannel channel) async {
  try {
    for (int i = 0; i < embed.pages.length; i++) {
      await channel.sendMessage(MessageBuilder(embeds: [
        embed.build(i),
      ]));
    }

    return true;
  } catch (e) {
    Logger.warn("Pagination", "Unable to dump pagination: $e");
    return false;
  }
}

Future<bool> respondWithPagination(ChatContext context, PaginatedEmbedBuilder embed, {ResponseLevel? level, Duration timeLimit = const Duration(seconds: 60), bool notifyIfNotOwner = true, required ServerSettings? settings}) async {
  final hasPages = embed.pages.length > 1;
  Logger.print("Pagination", "Pagination session with user ${context.user.id} started. context=${context.runtimeType}, hasPages=$hasPages");

  Modlog.add(ModlogEvent(
    "pagination",
    severity: ModlogSeverity.verbose,
    guild: context.guild,
    settings: settings,
    title: "Pagination Start",
    fields: {
      "Who": "<@${context.user.id}>",
      "Channel": "<#${context.channel.id}>",
      "Pages": "${embed.pages.length} (hasPages=`$hasPages`)",
      "Time Limit": timeLimit.toString(),
      "Context": "`${context.runtimeType}`",
      "Embed Title": embed.title ?? null.toDiscordCodeBlock(),
    },
  ));

  int page = 0;
  int secondsRemaining = timeLimit.inSeconds; // 5 minutes

  Future<void> Function() onTimeUp = () async {
    Logger.warn("Pagination", "Pagination session with user ${context.user.id} has not set onTimeUp at this point. The paginated embed will appear broken.");
  };

  final countdown = Timer.periodic(Duration(seconds: 1), (timer) {
    secondsRemaining--;

    if (secondsRemaining <= 0) {
      Logger.print("Pagination", "Pagination session with user ${context.user.id} hit time limit.");
      onTimeUp.call();
      timer.cancel();
    }
  });

  final Map<String, String> emojis = {
    "backAll": "⏪",
    "back": "◀️",
    "forward": "▶️",
    "forwardAll": "⏩",
    //"input": "🔢",
    "stop": "⏹️",
  };

  bool hasPerms(Snowflake userId) {
    return isOwner(id: userId) || context.user.id == userId;
  }

  if (context is MessageChatContext) {
    final m = await context.respond(MessageBuilder(
      embeds: [embed.build(page)],
    ), level: level);

    if (hasPages) {
      Future<void> update() async {
        secondsRemaining = 300;

        try {
          await m.edit(MessageUpdateBuilder(
            embeds: [embed.build(page)],
          ));
        } catch (e) {
          Logger.warn("Pagination", "Error with message ${m.id} update: $e");
        }
      }

      for (final x in emojis.entries) {
        await m.react(ReactionBuilder(name: x.value, id: null));
      }

      final controller = StreamController<DispatchEvent>();
      secondsRemaining = 300;

      onTimeUp = () async {
        await m.deleteAllReactions();
        controller.close();
      };

      StreamGroup.merge([
        context.client.onMessageReactionAdd,
        context.client.onMessageReactionRemove,
      ]).listen(
        (event) => controller.isClosed ? null : controller.add(event),
        onDone: () => controller.close(),
      );

      outer: await for (final x in controller.stream) {
        final context = (
          emoji: x is MessageReactionAddEvent ? x.emoji : (x is MessageReactionRemoveEvent ? x.emoji : null),
          userId: x is MessageReactionAddEvent ? x.userId : (x is MessageReactionRemoveEvent ? x.userId : null),
          guild: x is MessageReactionAddEvent ? x.guild : (x is MessageReactionRemoveEvent ? x.guild : null),
        );

        if (!hasPerms(context.userId!)) continue;
        final entry = emojis.entries.firstWhereOrNull((y) => y.value == context.emoji?.name)?.key;
        if (entry == null) continue;

        switch (entry) {
          case "backAll":
            page = 0;
            await update();
            break;
          case "forwardAll":
            page = embed.pages.length - 1;
            await update();
            break;
          case "back":
            page--;
            if (page < 0) page = 0;
            await update();
            break;
          case "forward":
            page = page + 1;
            if (page >= embed.pages.length) page = embed.pages.length - 1;
            await update();
            break;
          case "stop":
            try {
              await m.deleteAllReactions();
            } catch (_) {
              Logger.print("Pagination", "Falling back on deleting ${emojis.length} self-reactions...");
              await m.react(ReactionBuilder(name: "🛑", id: null));

              for (final x in emojis.entries) {
                try {
                  await m.deleteOwnReaction(ReactionBuilder(id: null, name: x.value));
                } catch (e) {
                  Logger.warn("Pagination", "Unable to delete self-reaction ${x.key} on message ${m.id}: $e");
                }
              }
            }

            break outer;
          case "input":
            // TODO
            await update();
            break;
        }
      }
    }
  } else if (context is InteractionChatContext) {
    List<ComponentBuilder<Component>> buildComponents() {
      List<ComponentBuilder<Component>> results = [];

      for (final x in emojis.entries) {
        results.add(ButtonBuilder.primary(customId: "${x.key}.${context.interaction.id}", emoji: TextEmoji(
          id: Snowflake.zero,
          manager: context.client.application.emojis,
          name: x.value,
        ), isDisabled: !switch (x.key) {
          // For each expression, the button is enabled if true.
          "back" || "backAll" => page != 0,
          "forward" || "forwardAll" => page != embed.pages.length - 1,
          _ => true,
        }));
      }

      return results;
    }

    await context.respond(MessageBuilder(
      embeds: [embed.build(page)],
      components: hasPages ? [ActionRowBuilder(components: buildComponents())] : [],
    ));

    if (hasPages) {
      Future<void> update(MessageComponentInteraction interaction, {bool stop = false}) async {
        secondsRemaining = 300;

        try {
          await interaction.respond(MessageUpdateBuilder(
            embeds: [embed.build(page)],
            components: stop ? [] : [ActionRowBuilder(components: buildComponents())],
          ), updateMessage: true);
        } catch (e) {
          Logger.warn("Pagination", "Error with interaction ${interaction.id} update: $e");
        }
      }

      final controller = StreamController<InteractionCreateEvent<MessageComponentInteraction>>();
      MessageComponentInteraction? interaction;
      secondsRemaining = 300;

      onTimeUp = () async {
        if (interaction == null) await context.interaction.updateOriginalResponse(MessageUpdateBuilder(components: []));
        else await interaction.updateOriginalResponse(MessageUpdateBuilder(components: []));
        controller.close();
      };

      context.client.onMessageComponentInteraction.listen(
        (event) => controller.isClosed ? null : controller.add(event),
        onDone: () => controller.close(),
      );

      outer: await for (final event in controller.stream) {
        final customId = event.interaction.data.customId;
        final condition = emojis.entries.any((x) => customId == "${x.key}.${context.interaction.id}");
        final userId = event.interaction.user?.id ?? event.interaction.member?.id;

        if (userId == null || !hasPerms(userId)) {
          if (notifyIfNotOwner) {
            await event.interaction.respond(MessageBuilder(content: "You are not the owner of this embed.", flags: MessageFlags.ephemeral));
            await Future.delayed(Duration(seconds: 2));
            await event.interaction.deleteOriginalResponse();
          }

          continue;
        }

        Logger.print("Pagination", "Found event (${event.runtimeType}) with interaction ${event.interaction.id} with ID $id ($condition)");
        if (!condition) continue;
        interaction = event.interaction;

        switch (customId.split(".").first) {
          case "backAll":
            page = 0;
            await update(event.interaction);
            break;
          case "forwardAll":
            page = embed.pages.length - 1;
            await update(event.interaction);
            break;
          case "back":
            page--;
            if (page < 0) page = 0;
            await update(event.interaction);
            break;
          case "forward":
            page = page + 1;
            if (page >= embed.pages.length) page = embed.pages.length - 1;
            await update(event.interaction);
            break;
          case "stop":
            await update(event.interaction, stop: true);
            break outer;
          case "input":
            // TODO
            await update(event.interaction);
            break;
        }
      }
    }
  } else {
    throw UnimplementedError();
  }

  Modlog.add(ModlogEvent(
    "pagination",
    severity: ModlogSeverity.verbose,
    guild: context.guild,
    settings: settings,
    title: "Pagination End",
    fields: {
      "Who": "<@${context.user.id}>",
      "Channel": "<#${context.channel.id}>",
      "Tick": "${countdown.isActive ? countdown.tick : null.toDiscordCodeBlock()}",
    },
  ));

  Logger.print("Pagination", "Pagination session with user ${context.user.id} ended.");
  if (countdown.isActive) countdown.cancel();
  return true;
}