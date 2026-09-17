import 'dart:async';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';

class JarvisPlugin extends BotPlugin {
  @override get info => BotPluginInfo(id: "jarvis", version: Version.parse("1.0.0A"), description: "Jarvis, destroy their house");

  static const padding = 20;
  static const maxLines = 3;
  static final fonts = [arial48, arial24, arial14];

  Image? template;

  int measure(BitmapFont font, String text) {
    int width = 0;

    for (final rune in text.runes) {
      final glyph = font.characters[rune];
      if (glyph != null) width += glyph.xAdvance;
    }

    return width;
  }

  List<String> wrap(BitmapFont font, String text, int max) {
    final words = text.split(' ');
    final List<String> lines = [];
    String current = "";

    for (final word in words) {
      final text = current.isEmpty ? word : '$current $word';

      if (measure(font, text) <= max) {
        current = text;
      } else {
        if (current.isNotEmpty) lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  @override
  FutureOr<List<BotConverter<dynamic>>> converters(CommandsPlugin plugin, KVStore store) {
    return [
      GreedyString.converter(),
    ];
  }

  @override
  FutureOr<List<BotCommand<Function>>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      BotCommand("jarvis", "Fun", "Jarvis, destroy their house", (T context, GreedyString data) async {
        try {
          final text = "jarvis, ${data.data}";

          if (template == null) {
            Logger.print("MrBeast", "Fetching template...");
            final response = await http.get(Uri.parse("https://raw.githubusercontent.com/Calebh101/calebh101_discord/main/assets/jarvis.jpg"));
            if (response.statusCode > 210 || response.statusCode < 200) throw Exception("Invalid status code: ${response.statusCode}");
            template = decodeJpg(response.bodyBytes);
          }

          if (template == null) {
            throw Exception("Template not generated: ${template.runtimeType}");
          }

          final image = copyRotate(template!, angle: 0);
          var font = fonts.first;

          int fontI = 0;
          List<String>? lines;
          int y = padding;

          while (lines == null || lines.length > maxLines) {
            font = fonts[fontI];
            lines = wrap(font, text, image.width - 20);
            fontI++;

            if (fonts.length == fontI) {
              break;
            }
          }

          for (final line in lines!) {
            final width = measure(font, line);
            final x = (image.width - width) ~/ 2;

            drawString(image, line, font: font, x: x, y: y, color: ColorRgb8(0, 0, 0));
            y += font.lineHeight;
          }

          await context.respond(MessageBuilder(attachments: [
            AttachmentBuilder(data: encodePng(image), fileName: "jarvis-${text.hashCode}.png"),
          ]));
        } catch (e, t) {
          Logger.error("Jarvis", e, trace: t);
          context.respondWithError("We couldn't generate an image.");
        }
      }),
    ];
  }
}