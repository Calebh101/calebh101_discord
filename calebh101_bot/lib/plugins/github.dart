import 'dart:async';

import 'package:calebh101_bot/main.dart';
import 'package:calebh101_discord/calebh101_discord.dart';

class GitHubPlugin extends BotPluginLegacy {
  GitHubPlugin() : super(id: "github", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("github", "GitHub", "Send a GitHub repo.", (ChatContext context, String arg1, [String? arg2, GreedyString? addons]) async {
        await context.respond(MessageBuilder(content: "https://gh.calebh101.net${[arg1, ?arg2].map((x) => "/$x").join("")}${addons?.data ?? ""}"));
      }, aliases: ["gh"]),

      BotCommand("githubchannel", "GitHub", "Get the current channel for GitHub updates.", (T context) async {
        final settings = GitHubServerSettings(store, context.guild!.id);
        final id = settings.githubChannel.get();

        await context.respond(MessageBuilder(content: id != null ? "GitHub updates channel: ${id.value.toChannel()}" : "No GitHub updates channel set."));
      }, needsGuild: true),

      BotCommand("setgithubchannel", "GitHub", "Set the current channel for GitHub updates.", (T context, [GuildTextChannel? channel]) async {
        final settings = GitHubServerSettings(store, context.guild!.id);
        settings.githubChannel.set(channel?.id);

        await context.respond(MessageBuilder(content: "GitHub updates channel ${channel != null ? "set to ${channel.toMention()}" : "**reset**"}."));
      }, needsGuild: true, permissionsRequired: BotCommandPermissions.admin),
    ];
  }
}

class GitHubServerSettings extends Calebh101BotServerSettings {
  GitHubServerSettings(super.store, super.id);

  SettingsObject<Snowflake> get githubChannel => SettingsObject.snowflake(this, "githubChannel");
}