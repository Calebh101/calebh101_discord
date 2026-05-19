import 'package:calebh101_discord/calebh101_discord.dart';

abstract class ConverterType {
  const ConverterType();

  String get name;
  String get info;

  static ConverterType? lookup<T>(T input) {
    if (input is ConverterType) return input;
    return null;
  }
}

extension GetConverterType on Object? {
  ConverterType? lookupConverterType() {
    return ConverterType.lookup(this);
  }
}

class StringList extends ConverterType {
  final List<String> data;
  const StringList(this.data);

  @override
  String get name => "Item List";

  @override
  String get info => "A comma-separated value list.";

  List<String> validate(List<String> allowed) {
    return data.where((x) => allowed.contains(x)).toList();
  }

  int invalid(List<String> allowed) {
    return data.where((x) => !allowed.contains(x)).length;
  }

  @override
  String toString() {
    return "$data";
  }

  static BotConverter converter() {
    return BotConverter("StringList", (_) => Converter<StringList>((value, context) {
      final data = value.getQuotedWord().split(",").map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (data.isNotEmpty) return StringList(data);
      return null;
    }));
  }
}

class GreedyStringList extends StringList {
  const GreedyStringList(super.data);

  static BotConverter converter() {
    return BotConverter("GreedyStringList", (_) => Converter<GreedyStringList>((value, context) {
      final data = value.remaining.split(",").map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      value.index = value.end;
      if (data.isNotEmpty) return GreedyStringList(data);
      return null;
    }));
  }
}

class GreedyString extends ConverterType {
  final String data;
  const GreedyString(this.data);

  @override
  String get name => "Greedy String";

  @override
  String get info => "Takes up the remaining input in the command as one string. Does not need quotes.";

  @override
  String toString() {
    return data;
  }

  static BotConverter converter() {
    return BotConverter("GreedyString", (_) => Converter<GreedyString>((value, context) {
      if (value.remaining.trim().isEmpty) return null;
      final result = GreedyString(trimMatchingQuotes(value.remaining.trim()));
      value.index = value.end;
      return result;
    }));
  }

  static String trimMatchingQuotes(String input) {
    if (input.length >= 2) {
      if ((input.startsWith('"') && input.endsWith('"')) || (input.startsWith("'") && input.endsWith("'"))) {
        return input.substring(1, input.length - 1);
      }
    }

    return input;
  }
}

class NoArgs extends ConverterType {
  const NoArgs();

  @override
  String get name => "No arguments";

  @override
  String get info => "Makes sure no arguments are passed.";

  static BotConverter converter() {
    return BotConverter("NoArgs", (plugin) => Converter<NoArgs>((value, context) {
      final remaining = value.remaining.trim();
      if (remaining.isNotEmpty) return null;
      return NoArgs();
    }));
  }
}

class GreedyQuotedList extends ConverterType {
  final List<String> input;
  const GreedyQuotedList(this.input);

  @override
  String get name => "Greedy quoted list";

  @override
  String get info => "List of quoted words.";

  static BotConverter converter() {
    return BotConverter("GreedyQuotedList", (plugin) => Converter<GreedyQuotedList>((value, context) {
      List<String> results = [];

      while (value.remaining.trim().isNotEmpty) {
        results.add(value.getQuotedWord());
      }

      return GreedyQuotedList(results);
    }));
  }
}

class GreedyRoleList extends ConverterType {
  final List<Role> input;
  const GreedyRoleList(this.input);

  @override
  String get name => "Greedy list of roles";

  @override
  String get info => "List of roles.";

  static BotConverter converter() {
    return BotConverter("GreedyRoleList", (plugin) => Converter<GreedyRoleList>((value, context) async {
      final converter = plugin.getConverter(RuntimeType<Role>())!;
      List<Role> results = [];

      while (value.remaining.trim().isNotEmpty) {
        try {
          final role = await converter.convert.call(value, context);
          results.add(role!);
        } catch (_) {}
      }

      return GreedyRoleList(results);
    }));
  }
}

class GreedyMemberList extends ConverterType {
  final List<Member> input;
  const GreedyMemberList(this.input);

  @override
  String get name => "Greedy list of members";

  @override
  String get info => "List of members.";

  static BotConverter converter() {
    return BotConverter("GreedyMemberList", (plugin) => Converter<GreedyMemberList>((value, context) async {
      final converter = plugin.getConverter(RuntimeType<Member>())!;
      List<Member> results = [];

      while (value.remaining.trim().isNotEmpty) {
        try {
          final user = await converter.convert.call(value, context);
          results.add(user!);
        } catch (_) {}
      }

      return GreedyMemberList(results);
    }));
  }
}

class GreedyGuildTextChannelList extends ConverterType {
  final List<GuildTextChannel> input;
  const GreedyGuildTextChannelList(this.input);

  @override
  String get name => "Greedy list of channels";

  @override
  String get info => "List of channels.";

  static BotConverter converter() {
    return BotConverter("GreedyGuildTextChannelList", (plugin) => Converter<GreedyGuildTextChannelList>((value, context) async {
      if (value.remaining.trim() == "allInGuild" && context.guild != null) {
        value.index = value.end;
        return GreedyGuildTextChannelList((await context.guild!.fetchChannels()).whereType<GuildTextChannel>().toList());
      }

      final converter = plugin.getConverter(RuntimeType<GuildTextChannel>())!;
      List<GuildTextChannel> results = [];

      while (value.remaining.trim().isNotEmpty) {
        try {
          final channel = await converter.convert.call(value, context);
          results.add(channel!);
        } catch (_) {}
      }

      value.index = value.end;
      return GreedyGuildTextChannelList(results);
    }));
  }
}

BotConverter durationConverter() {
  return BotConverter("duration", (_) => Converter<Duration>((value, context) {
    final text = value.getQuotedWord();
    return parseDuration(text);
  }));
}

BotConverter dateTimeConverter() {
  return BotConverter("datetime", (_) => Converter<DateTime>((value, context) {
    final text = value.getQuotedWord();
    return parseDateTime(text);
  }));
}

BotConverter numConverter() {
  return BotConverter("num", (plugin) => plugin.getConverter(RuntimeType<num>()));
}

class Or<A, B> extends ConverterType {
  final A? $1;
  final B? $2;

  const Or(this.$1, this.$2);

  @override
  String get info => "$A or $B";

  @override
  String get name => "$A or $B";

  T? getForEach<T>(T Function(A input) a, T Function(B input) b) {
    if ($1 != null) return a($1!);
    if ($2 != null) return b($2!);
    return null;
  }

  static BotConverter converter<A, B>() {
    return BotConverter("Or<$A, $B>", (plugin) => Converter<Or<A, B>>((value, context) async {
      A? a;
      B? b;

      final indexBefore = value.index;
      final ca = plugin.getConverter(RuntimeType<A>());
      if (ca != null) a = await ca.convert.call(value, context);

      if (a == null) {
        value.index = indexBefore;
        final cb = plugin.getConverter(RuntimeType<B>());
        if (cb != null) b = await cb.convert.call(value, context);
      }

      return a != null || b != null ? Or<A, B>(a, b) : null;
    }));
  }
}