import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';

class VideoPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "videos", version: Version.parse("1.0.0A"), description: "Stuff for videos.");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("youtube", "Videos", "Turn a youtube link into a raw video via embed.", (T context, [String? input]) async {
        if (input == null) {
          input = context.ifIs<MessageChatContext>()?.message.referencedMessage?.content;
          if (input == null) return context.respondWithError("No input found! You need to either input a YouTube link or reply to a message with a YouTube link.");
        }

        final original = input;
        input = input.split("/").last;

        if (input.startsWith("watch?v=")) {
          input = input.replaceFirst("watch?v=", "");
        } else {
          input = input.split("?").first;
        }

        Logger.print("YouTube", "Input: $original\nOutput: $input");
        final message = await context.respond(.new(content: "Fetching your video...\n-# ID: `$input`"));

        try {
          final process = await Process.run(
            "yt-dlp",
            [
              "-f", "bestvideo+bestaudio",
              "--merge-output-format", "mp4",
              "-o", "/tmp/discord-youtube-video-$input.mp4",
              "https://www.youtube.com/watch?v=$input",
            ],
          );

          if (process.exitCode != 0) throw Exception(process.stderr);
          final file = File("/tmp/discord-youtube-video-$input.mp4");
          Logger.print("YouTube", "Generated file for input $input: ${file.path}");

          await context.updateMessage(message, .new(
            content: "https://files.calebh101.net/discord/youtube/$input",
          ));

          Timer(.new(minutes: 10), () async {
            try {
              if (await file.exists()) {
                Logger.print("YouTube", "Deleting file ${file.path}...");
                await file.delete();
              }
            } catch (e) {
              Logger.warn("YouTube", "Error deleting file ${file.path} ($input): $e");
            }
          });
        } catch (e) {
          Logger.warn("YouTube", "Error fetching video $input: $e");
          await context.updateMessage(message, .new(content: "We couldn't fetch that video. Make sure you inputted a valid YouTube link or video ID and try again."));
        }
      }, aliases: ["yt"]),
    ];
  }
}