import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';

class MrBeastThumbnailRaw {
  final String path;
  final String type;
  final Uri url;

  const MrBeastThumbnailRaw({required this.path, required this.type, required this.url});
}

class MrBeastThumbnail {
  final String path;
  final Uri url;

  const MrBeastThumbnail({required this.path, required this.url});
}

class MrBeastPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "mrbeast", version: Version.parse("1.0.0A"), description: "MrBeast");

  List<MrBeastThumbnail>? thumbnails;
  Image? template;

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      Or.converter<Uri, GreedyString>(),
      uriConverter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("mrbeast", "Fun", "MRBEAST GIMME MONEY", (T context, [Or<Uri, GreedyString>? arg1, GreedyString? arg2]) async {
        var uri = arg1?.$1;
        final title = arg1?.$2?.data ?? arg2?.data;

        if (uri == null && context is MessageChatContext && context.message.referencedMessage != null) {
          final message = context.message.referencedMessage!;

          final attachment = message.attachments.firstWhereOrNull((x) => x.contentType?.startsWith("image/") ?? false);
          final embed = message.embeds.firstWhereOrNull((x) => x.image?.url != null || x.thumbnail?.url != null);
          final image = attachment?.url ?? embed?.image?.url ?? embed?.thumbnail?.url;

          if (image != null) {
            uri = image;
          }
        }

        if (uri == null && context is MessageChatContext) {
          final attachment = context.message.attachments.firstWhereOrNull((x) => x.contentType?.startsWith("image/") ?? false);
          uri= attachment?.url;
        }

        if (uri == null) return context.respondWithError("Please pass the URL of an image, or reply to a message with an image.");

        try {
          if (thumbnails == null) {
            Logger.print("MrBeast", "Fetching thumbnails...");
            final response = await http.get(Uri.parse("https://api.github.com/repos/MagicJinn/MrBeastify-Youtube/git/trees/main?recursive=1"));
            if (response.statusCode > 210 || response.statusCode < 200) throw Exception("Invalid status code (action=thumbnails): ${response.statusCode}");
            final body = jsonDecode(response.body);

            thumbnails = (body["tree"] as List).map((x) {
              return MrBeastThumbnailRaw(path: x["path"], type: x["type"], url: Uri.parse(x["url"]));
            }).where((x) => x.path.startsWith("images") && x.type == "blob").map((x) {
              return MrBeastThumbnail(path: x.path, url: Uri.parse("https://raw.githubusercontent.com/MagicJinn/MrBeastify-Youtube/main/${x.path}"));
            }).toList();
          }

          if (template == null) {
            Logger.print("MrBeast", "Fetching template...");
            final response = await http.get(Uri.parse("https://raw.githubusercontent.com/Calebh101/calebh101_discord/main/assets/youtube.png"));
            if (response.statusCode > 210 || response.statusCode < 200) throw Exception("Invalid status code (action=thumbnails): ${response.statusCode}");
            template = decodePng(response.bodyBytes);
          }

          final thumbnail = thumbnails!.elementAt(Random().nextInt(thumbnails!.length));
          Logger.print("MrBeast", "Found ${thumbnails?.length} thumbnails, and decided on: ${thumbnail.path} (${thumbnail.url})\nTitle inputted: $title");

          final response = await http.get(uri);
          if (response.statusCode > 210 || response.statusCode < 200) throw Exception("Invalid status code (uri=$uri): ${response.statusCode}");
          var base = decodeImage(response.bodyBytes)!;

          final response2 = await http.get(thumbnail.url);
          if (response2.statusCode > 210 || response2.statusCode < 200) throw Exception("Invalid status code (uri=${thumbnail.url}): ${response.statusCode}");
          final overlay = decodeImage(response2.bodyBytes)!;

          final resizedOverlay = copyResize(
            overlay,
            width: base.width,
            height: base.height,
          );

          compositeImage(
            base,
            resizedOverlay,
            dstX: 0,
            dstY: 0,
          );

          if (title != null) {
            final image = copyRotate(template!, angle: 0);

            compositeImage(
              image,
              copyResize(
                base,
                width: 3418,
                height: 1950,
              ),
              dstX: 40,
              dstY: 40,
            );

            resize(
              image,
              width: (image.width / 2).round(),
              height: (image.height / 2).round(),
            );

            base = image;
            drawString(base, title, font: arial48, y: 1050, x: 25, color: ColorRgb8(0, 0, 0));
          }

          await context.respond(MessageBuilder(attachments: [
            AttachmentBuilder(data: encodePng(base), fileName: thumbnail.path.split("/").last),
          ]));
        } catch (e, t) {
          Logger.error("MrBeast", "uri=$uri: $e", trace: t);
          context.respondWithError("We couldn't generate a thumbnail.");
        }
      }),
    ];
  }
}