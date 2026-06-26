import 'dart:async';
import 'dart:typed_data';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:collection/collection.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

class ComicsPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "comics", version: Version.parse("1.0.0A"), description: "Comics!");

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("garfield", "Comics", "Combine three random frames of Garfield comics into one. Powered by: https://www.bgreco.net/garfield", (T context) async {
        final url = await getImage();
        if (url == null) return context.respondWithError("We couldn't get the Garfield comic for today.");
        late Uint8List data;

        try {
          final response = await http.get(url);
          if (response.statusCode < 200 || response.statusCode > 210) throw Exception("Invalid status code: ${response.statusCode} (body=${response.body})");
          data = response.bodyBytes;
        } catch (e) {
          Logger.warn("Comics", "Unable to get Garfield comic image (url=$url): $e");
          return;
        }

        await context.respond(MessageBuilder(
          content: "-# Powered by: https://www.bgreco.net/garfield",
          attachments: [
            AttachmentBuilder(data: data, fileName: "garfield.png"),
          ],
        ));
      }),
    ];
  }

  Future<Uri?> getImage() async {
    final url = Uri.parse("https://www.bgreco.net/garfield");
    late http.Response response;

    try {
      response = await http.get(url);
      if (response.statusCode < 200 || response.statusCode > 210) throw Exception("Invalid status code: ${response.statusCode} (body=${response.body})");
    } catch (e) {
      Logger.warn("Comics", "Unable to get Garfield: $e");
      return null;
    }

    final document = html.parse(response.body);
    final element = document.querySelectorAll('a').firstWhereOrNull((x) => x.text.trim().toLowerCase() == "save this comic");
    final imageUrl = element?.attributes['href'];

    Logger.print("Comics", "Found comic URL of $imageUrl");
    if (imageUrl == null) throw Exception('Could not find comic image');

    return Uri.parse("$url/$imageUrl");
  }
}