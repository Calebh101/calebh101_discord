import 'package:calebh101_discord/calebh101_discord.dart';

class StringList {
  final List<String> data;
  const StringList(this.data);

  List<String> validate(List<String> allowed) {
    return data.where((x) => allowed.contains(x)).toList();
  }

  int invalid(List<String> allowed) {
    return data.where((x) => !allowed.contains(x)).length;
  }

  static BotCommand converter() {
    return BotCommand.converter((_) => Converter<StringList>((value, context) {
      final data = value.getQuotedWord().split(",").map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (data.isNotEmpty) return StringList(data);
      return null;
    }));
  }
}