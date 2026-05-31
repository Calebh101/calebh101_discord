import 'dart:async';
import 'dart:math';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:chrono_dart/chrono_dart.dart';

Future<DiscordColor> getColor(Member? member) async {
  return await getPrimaryColor(member) ?? primaryBotColor;
}

extension Flatten<T> on Iterable<Iterable<T>> {
  Iterable<T> flatten() => expand((e) => e);
}

extension ToFuture<T> on FutureOr<T> {
  Future<T> toFuture() async {
    return this;
  }
}

extension ToFutureOr<T> on Future<T> {
  FutureOr<T> toFutureOr() async {
    return this;
  }
}

Future<String> Function(MessageCreateEvent) prefixFromServerSettings(ServerSettings? Function(PartialGuild guild) getSettings) => (MessageCreateEvent event) async {
  return [() {
    if (event.guild == null) return defaultPrefix;
    final settings = getSettings.call(event.guild!);
    if (settings == null) return defaultPrefix;

    final prefix = settings.prefix.get();
    return prefix;
  }(), if (dev) "d"].join("");
};

BotConverter<T> enumConverter<T extends Enum>(List<T> values) => BotConverter("enum.$T", (plugin) => Converter<T>(
  (value, context) {
    final input = value.getQuotedWord();

    for (final x in values) {
      if (x.name == input) {
        return x;
      }
    }

    return null;
  },
  choices: values.map(
    (e) => CommandOptionChoiceBuilder(name: e.name, value: e.name),
  ).toList(),
));

Future<Member?> userToMember(User? user, {required Guild? guild}) async {
  if (user == null || guild == null) return null;

  try {
    return await guild.members.get(user.id);
  } catch (_) {
    return null;
  }
}

extension PrettyDuration on Duration {
  String pretty() {
    if (inSeconds < 60) return '${inSeconds}s';
    if (inMinutes < 60) return '${inMinutes}m ${inSeconds.remainder(60)}s';
    if (inHours < 24) return '${inHours}h ${inMinutes.remainder(60)}m';
    return '${inDays}d ${inHours.remainder(24)}h';
  }

  String prettyDetailed() {
    return ["${inDays}d", "${inHours.remainder(24)}h", "${inMinutes.remainder(60)}m", "${inSeconds.remainder(60)}s"].join(" ");
  }
}

extension GetMessages on MessageManager {
  Future<List<Message>> fetchManyUnlimited(int amount) async {
    assert(amount >= 1);
    List<Message> results = [];
    Snowflake? before;

    while (results.length < amount) {
      final limit = min(100, amount - results.length);
      final messages = await fetchMany(limit: limit, before: before);

      if (messages.isEmpty) break;
      results.addAll(messages);
      before = messages.last.id;
    }

    return results;
  }
}

Duration? parseDuration(String text) {
  final regex = RegExp(
    r'(?:(\d+)y)?(?:(\d+)mo)?(?:(\d+)w)?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?',
  );

  final match = regex.firstMatch(text);
  if (match == null) return null;

  return Duration(
    days: (int.tryParse(match[1] ?? '') ?? 0) * 365  // years
      + (int.tryParse(match[2] ?? '') ?? 0) * 30     // months ~
      + (int.tryParse(match[3] ?? '') ?? 0) * 7      // weeks
      + (int.tryParse(match[4] ?? '') ?? 0),         // days
    hours: int.tryParse(match[5] ?? '') ?? 0,
    minutes: int.tryParse(match[6] ?? '') ?? 0,
    seconds: int.tryParse(match[7] ?? '') ?? 0,
  );
}

DateTime? parseDateTime(String text) {
  return Chrono.parseDate(text);
}

int levenshtein(String a, String b) {
  final m = a.length, n = b.length;
  final dp = List.generate(m + 1, (i) => List.filled(n + 1, 0));

  for (int i = 0; i <= m; i++) dp[i][0] = i;
  for (int j = 0; j <= n; j++) dp[0][j] = j;

  for (int i = 1; i <= m; i++) {
    for (int j = 1; j <= n; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = 1 + [dp[i-1][j], dp[i][j-1], dp[i-1][j-1]].reduce(min);
      }
    }
  }

  return dp[m][n];
}

double fuzzyScore(String query, String result) {
  final queryWords = query.toLowerCase().split(' ');
  final resultWords = result.toLowerCase().split(' ');
  double totalScore = 0;

  for (final qWord in queryWords) {
    int bestDistance = queryWords.fold(999, (best, _) => best);

    for (final rWord in resultWords) {
      final dist = levenshtein(qWord, rWord);
      if (dist < bestDistance) bestDistance = dist;
    }

    totalScore += 1 - (bestDistance / max(qWord.length, 1));
  }

  return totalScore / queryWords.length;
}

Future<void> alertOwners(NyxxGateway client, EmbedBuilder embed) async {
  if (globalOwners == null) return;

  for (final owner in globalOwners!) {
    try {
      final user = await client.users.get(owner.id);
      final channel = await client.users.createDm(user.id);
      await channel.sendMessage(MessageBuilder(embeds: [embed]));
    } catch (e) {
      Logger.warn("AlertOwner", "Error: $e");
    }
  }
}

extension IfIs on Object? {
  T? ifIs<T>() => this is T ? this as T : null;
}
