import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:async/async.dart';
import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:calebh101_discord/src/logger_override.dart';
import 'package:collection/collection.dart';
import 'package:localpkg/classes.dart';

late DiscordColor primaryBotColor;

List<T> flatten<T>(List<List<T>> lists) => lists.expand((e) => e).toList();

String randomPingPhrase(Map<String? Function(MessageCreateEvent event), num> phrases, MessageCreateEvent event) {
  while (true) {
    final total = phrases.values.reduce((a, b) => a + b);
    final random = Random().nextDouble() * total;
    num cumulative = 0;

    for (final entry in phrases.entries) {
      cumulative += entry.value;

      if (random < cumulative) {
        final result = entry.key(event);
        if (result != null) return result;
        break;
      }
    }
  }
}

class BotContext {
  final NyxxGateway client;
  final User? bot;

  const BotContext({required this.client, required this.bot});
}

class BotCommand {
  final Command? command;
  final Converter? Function(CommandsPlugin plugin)? converter;

  const BotCommand.converter(this.converter) : command = null;

  BotCommand.command(Command this.command, CommandAttributes attributes) : converter = null {
    commandAttributesMap[command!.name] = attributes;
  }

  static Map<String, CommandAttributes> commandAttributesMap = {};

  static Map<String, int> getAllCategories() {
    Map<String, int> results = {};

    for (final x in commandAttributesMap.entries) {
      results[x.value.category] = (results[x.value.category] ?? 0) + 1;
    }

    return results;
  }
}

enum BotCommandPermissions {
  any,
  admin,
  claimer,
  owner,
}

class CommandAttributes {
  final BotCommandPermissions permissionsRequired;
  final String category;

  const CommandAttributes({this.permissionsRequired = BotCommandPermissions.any, required this.category});
}

class TerminalCommand {
  final Char key;
  final void Function() callback;

  const TerminalCommand(this.key, this.callback);
}

/// Create a new gateway and bot.
///
/// [settings] is a [BotSettings] object. To use the default settings, just input `BotSettings()`. However, you can extend [BotSettings] and add your own fields.
///
/// [prefix] is the message prefix. If this has a value, you will be able to either mention the bot, or use the specific prefix in your message. Otherwise, only slash commands will be available.
///
/// [commands] is a list of [Command] objects. These will be registered as slash commands and optionally able to be used with prefixes.
///
/// [permissions] is a list of permissions. For bot apps, you should start out with `[...GatewayIntents.allUnprivileged, GatewayIntents.messageContent]`.
///
/// [createBot] will create a bot user using `client.user.get()` if true.
Future<BotContext?> load({required BotSettings settings, required FutureOr<Pattern> Function(MessageCreateEvent)? prefix, List<BotCommand>? Function(CommandsPlugin plugin)? commands, required List<Flag<GatewayIntents>> permissions, bool createBot = true, List<TerminalCommand> terminalCommands = const [], required DefinedUser owner, required KVStore store, required DiscordColor primaryColor}) async {
  primaryBotColor = primaryColor;
  if (!(await settings.initCore())) return null;
  if (!(await settings.init())) return null;
  loggerOverride();

  final token = await settings.botToken.getAsync();
  Flags<GatewayIntents> intents = Flag(0);
  final cmd = CommandsPlugin(prefix: prefix);

  for (final c in commands?.call(cmd) ?? []) {
    if (c.command != null) cmd.addCommand(c.command!);

    if (c.converter != null) {
      final x = c.converter!.call(cmd);

      if (x != null) {
        cmd.addConverter(x);
        Logger.print("Commands", "Added convertor ${x.runtimeType}");
      }
    }
  }

  for (final x in permissions) {
    intents = intents | x;
  }

  if (token == null) {
    Logger.warn("load", "No token provided!");
    return null;
  }

  final client = await Nyxx.connectGateway(
    token, intents,
    options: GatewayClientOptions(plugins: [cliIntegration, cmd]),
  );

  final user = createBot ? await client.user.get() : null;

  cmd.onCommandError.listen((e) async {
    if (e is CommandNotFoundException) return;
    Logger.warn("Commands", "Command error: $e (error: ${e.runtimeType}, context: ${e is ContextualException ? e.context.runtimeType : null})", trace: e.stackTrace);

    void handleError<T extends ContextualException>(T e, String message, {String? codeblock, String? codeblocklang, bool showHelp = false}) {
      if (e.context is! MessageChatContext) return;
      final context = e.context as MessageChatContext;
      if (context.guild == null) return;
      final settings = ServerSettings(store, context.guild!.id);

      context.respondWithError([
        message,
        if (codeblock != null) "```$codeblocklang\n$codeblock\n```",
        if (showHelp) "Run `${settings.prefix.get() ?? defaultPrefix}help ${context.command.name}` for more info.",
      ].join("\n"));
    }

    if (e is ConverterFailedException) {
      return handleError(e, "Invalid command input.", codeblock: "Could not parse input to type ${e.failed}.", showHelp: true);
    } else if (e is NotEnoughArgumentsException) {
      return handleError(e, "Not enough arguments.", showHelp: true);
    }

    if (e is ContextualException && e.context is MessageChatContext) {
      await (e.context as MessageChatContext).respond(MessageBuilder(
        content: "An unknown error has occurred.\n```${e.runtimeType}```",
      ));
    }
  });

  client.onMessageCreate.listen((event) async {
    if (user != null && event.message.content.trim() == "<@${user.id}>") {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final message = randomPingPhrase(pingPhrases, event);

      event.message.channel.sendMessage(MessageBuilder(referencedMessage: MessageReferenceBuilder(type: MessageReferenceType.defaultType, messageId: event.message.id), content: "$message\n-# Latency: ${formatLatency(latency)} (Real: ${formatLatency(realLatency)})"));
    }
  });

  final tcmd = [...[
    TerminalCommand(Char.from("q"), () async {
      Process.killPid(pid, ProcessSignal.sigint);
    }),
    TerminalCommand(Char.from("p"), () async {
      final latency = client.httpHandler.latency;
      final realLatency = client.httpHandler.realLatency;
      final gatewayLatency = client.gateway.latency;

      Logger.print("Ping", "HTTP latency: ${formatLatency(latency)}\nReal latency: ${formatLatency(realLatency)}\nGateway latency: ${formatLatency(gatewayLatency)}");
    }),
  ], ...terminalCommands];

  stdin.echoMode = false;
  stdin.lineMode = false;

  late List<StreamSubscription<ProcessSignal>> subscriptions;

  void onClose(ProcessSignal signal) {
    Logger.print("onClose", "Received ${signal.name}, closing...");
    stdin.echoMode = true;
    stdin.lineMode = true;

    for (var x in subscriptions) {
      x.cancel();
    }
  }

  subscriptions = [
    ProcessSignal.sigint.watch().listen(onClose),
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(onClose),
  ];

  stdin.listen((List<int> data) {
    for (final x in tcmd) {
      if (x.key.code == data[0]) {
        x.callback.call();
      }
    }
  });

  return BotContext(client: client, bot: user);
}

String? memberToString(Member? member, {bool detailed = false}) {
  if (member == null) return null;

  try {
    return [
      "**${member.nick ?? member.user?.globalName ?? member.user?.username ?? (throw UnimplementedError("Couldn't find a valid name for member."))}**",
      "(*${member.user?.username ?? (throw UnimplementedError("Couldn't find a valid username for member."))}*)",
      if (detailed) "(`${member.id}`)",
    ].join(" ");
  } catch (_) {
    return null;
  }
}

String? userToString(User? user, {bool detailed = false}) {
  if (user == null) return null;

  try {
    return [
      "**${user.globalName ?? user.username}** (*${user.username}*)",
      if (detailed) "(`${user.id}`)",
    ].join(" ");
  } catch (_) {
    return null;
  }
}

String userOrMemberToString(Member? member, User user, {bool detailed = false}) {
  return memberToString(member, detailed: detailed) ?? userToString(user, detailed: detailed) ?? "`${user.id}`";
}

String formatLatency(Duration latency) {
  return "${(latency.inMicroseconds / Duration.microsecondsPerMillisecond).toStringAsFixed(3)}ms";
}

Future<DiscordColor?> getPrimaryColor(Member? member) async {
  if (member == null) return null;
  final roles = await Future.wait(member.roles.map((id) => id.get()));
  final colored = roles.where((r) => r.colors.primary.value != 0).toList();
  if (colored.isEmpty) return null;
  colored.sort((a, b) => b.position.compareTo(a.position));
  return colored.first.colors.primary;
}

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

      if (currentPageLength > maxLinesPerPage) {
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
        results.add(ButtonBuilder.primary(customId: "${x.key}.${context.interaction.id}", label: x.value, isDisabled: !switch (x.key) {
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

extension ToDiscordCodeBlock on Object? {
  String toDiscordCodeBlock({String? language}) {
    return "```${language ?? ""}\n$this\n```";
  }
}