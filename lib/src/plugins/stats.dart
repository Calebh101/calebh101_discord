import 'dart:async';
import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';
import 'package:system_info2/system_info2.dart';

class StatsPlugin extends BotPluginLegacy {
  StatsPlugin() : super(id: "stats", version: Version.parse("1.0.0A"));

  @override
  FutureOr<List<BotCommand>> commands<T extends ChatContext>(CommandsPlugin plugin, KVStore store) {
    return [
      aboutCommand<T>(store),
      statusCommand<T>(),
      pingCommand<T>(),

      BotCommand("support", "Bot", "Check out support resources.", (T context) async {
        await context.respond(MessageBuilder(content: [
          if (globalHomepage != null) "Home page: $globalHomepage",
          if (globalSupportServer != null) "Support server: ${globalSupportServer!.invite}",
        ].nullIfEmpty?.join("\n") ?? "No support resources are available."));
      }),
    ];
  }

  BotCommand aboutCommand<T extends ChatContext>(KVStore? store) => BotCommand.command("about", "See stats about this bot.", (T context) async {
    final settings = store != null && context.guild != null ? ServerSettings(store, context.guild!.id) : null;
    final prefix = settings?.prefix.get() ?? defaultPrefix;
    final guilds = await Future.wait(context.client.guilds.cache.values.map((x) async => (guild: await x.fetch(withCounts: true), owner: await tryCatchA(() => x.owner.get()))));;

    await context.respond(MessageBuilder(
      content: [
        "**$globalBotName**: A bot that does something",
        "Version $botVersion by [Calebh101](<https://github.com/Calebh101>)",
        null,
        "Current prefix: `$prefix`",
        "To see all commands, run `help`.",
        null,
        "I have **${BotCommand.commandRegistry.length}** commands (**${BotCommand.commandRegistry.mapTo((k, v) => v.category).toSet().length}** categories)",
        "I'm in **${guilds.length}** guilds",
        "I know **${context.client.users.cache.length}** people",
        null,
        [
          "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion}".trim(),
          (() {
            final processor = SysInfo.cores.first;
            return "${processor.vendor} ${processor.name}".trim();
          }()),
          "Kernel: ${SysInfo.kernelName} ${SysInfo.kernelVersion} ${SysInfo.kernelArchitecture.name}"
        ].join("\n").trim().toDiscordCodeBlock(),
        null,
        "Built with [nyxx](<https://pub.dev/packages/nyxx>), running on Dart:",
        Platform.version.trim().toDiscordCodeBlock(),
      ].map((x) => x ?? "").join("\n"),
    ));
  }, CommandAttributes(category: "Bot"));

  BotCommand statusCommand<T extends ChatContext>() => BotCommand("status", "Bot", "See the bot's status.", (T context) async {
    const factor = 1024;
    final m = await context.respond(MessageBuilder(content: "Fetching status..."));
    Map<String, String> elements = {};

    final memory = await getMemory();
    final rss = ProcessInfo.currentRss;
    final maxRss = ProcessInfo.maxRss;
    final storage = await getStorage();

    String megabytes(num input) {
      return "${(input / (factor * factor)).toStringAsFixed(1)} MiB";
    }

    String gigabytes(num input) {
      return "${(input / (factor * factor * factor)).toStringAsFixed(1)} GiB";
    }

    elements["System"] = [
      "${SysInfo.operatingSystemName} ${SysInfo.kernelArchitecture} ${SysInfo.operatingSystemVersion} ${SysInfo.kernelVersion}".trim(),
      (() {
        final processor = SysInfo.cores.first;
        return "${processor.vendor} ${processor.name}".trim();
      }()),
      "Kernel: ${SysInfo.kernelName} ${SysInfo.kernelVersion} ${SysInfo.kernelArchitecture.name}",
      "Dart: ${Platform.version.trim()}",
    ].join("\n").trim();

    elements["Memory/Storage"] = [
      "Memory: ${gigabytes(memory.available)} available / ${gigabytes(memory.total)},",
      "Memory for this process: ${megabytes(rss)} used (max since started: ${megabytes(maxRss)})",
      "Storage: ${gigabytes(storage.free)} Free / ${gigabytes(storage.total)}",
    ].join("\n").trim();

    elements["Uptime"] = [
      "System: ${await () async {
        try {
          return getSystemUptime();
        } catch (e) {
          return "Error: $e";
        }
      }()}",
      "Process: ${DateTime.now().difference(started)}",
    ].join("\n").trim();

    elements["Machine"] = await getStatus() ?? "No machine-defined status found.";
    await context.updateMessage(m, MessageUpdateBuilder(content: elements.entries.map((x) => "### ${x.key}\n${x.value.toDiscordCodeBlock()}").join("\n")));
  });

  Future<({int free, int total})> getStorage() async {
    if (Platform.isMacOS || Platform.isLinux) {
      final result = await Process.run('df', ['-k', '/']);
      final parts = result.stdout.toString().trim().split('\n')[1].split(RegExp(r'\s+'));

      return (
        total: int.parse(parts[1]) * 1024,
        free: int.parse(parts[3]) * 1024,
      );
    } else if (Platform.isWindows) {
      final result = await Process.run('wmic', ['logicaldisk', 'where', 'DeviceID="C:"', 'get', 'Size,FreeSpace']);
      final parts = result.stdout.toString().trim().split('\n').last.trim().split(RegExp(r'\s+'));

      return (
        total: int.parse(parts[0]),
        free: int.parse(parts[1]),
      );
    } else {
      throw UnsupportedError('Unsupported OS: ${Platform.operatingSystem}');
    }
  }

  Future<({int free, int available, int total})> getMemory() async {
    if (Platform.isMacOS) {
      final totalResult = await Process.run('sysctl', ['-n', 'hw.memsize']);
      final total = int.parse(totalResult.stdout.toString().trim());

      final vmResult = await Process.run('vm_stat', []);
      final lines = vmResult.stdout.toString().split('\n');
      final pageSize = 16384; // macOS default page size

      int getPages(String key) {
        final line = lines.firstWhere((l) => l.contains(key), orElse: () => '0');
        return int.tryParse(line.split(':').last.trim().replaceAll('.', '')) ?? 0;
      }

      final a = (getPages('Pages free') + getPages('Pages inactive')) * pageSize;
      final free = getPages("Pages free") * pageSize;
      return (total: total, free: free, available: a);
    } else {
      return (
        total: SysInfo.getTotalPhysicalMemory(),
        free: SysInfo.getFreePhysicalMemory(),
        available: SysInfo.getAvailablePhysicalMemory(),
      );
    }
  }

  Future<Duration> getSystemUptime() async {
    if (Platform.isLinux) {
      final content = await File('/proc/uptime').readAsString();
      final seconds = double.parse(content.trim().split(' ')[0]);
      return Duration(milliseconds: (seconds * 1000).round());
    }

    if (Platform.isMacOS) {
      final result = await Process.run('sysctl', ['-n', 'kern.boottime']);
      final match = RegExp(r'sec = (\d+)').firstMatch(result.stdout as String);
      if (match == null) throw Exception('Could not parse kern.boottime');
      final bootEpoch = int.parse(match.group(1)!);
      final bootTime = DateTime.fromMillisecondsSinceEpoch(bootEpoch * 1000);
      return DateTime.now().difference(bootTime);
    }

    if (Platform.isWindows) {
      final result = await Process.run('powershell', [
        '-Command',
        '(Get-Date) - (gcim Win32_OperatingSystem).LastBootUpTime | Select-Object -ExpandProperty TotalSeconds',
      ]);

      final seconds = double.parse((result.stdout as String).trim());
      return Duration(milliseconds: (seconds * 1000).round());
    }

    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  BotCommand pingCommand<T extends ChatContext>() => BotCommand.command(
    "ping", "Pong!",
    (T context) async {
      final latency = context.client.httpHandler.latency;
      final realLatency = context.client.httpHandler.realLatency;
      final gatewayLatency = context.client.gateway.latency;

      final Map<String, String> keys = {
        "HTTP latency": formatLatency(latency),
        "Real latency": formatLatency(realLatency),
        if (gatewayLatency.inMicroseconds > 0) "Gateway latency": formatLatency(gatewayLatency),
      };

      await context.respond(MessageBuilder(content: "<@${context.user.id}>, pong!\n\n${keys.entries.map((x) {
        return "> ${x.key}: **${x.value}**";
      }).join("\n")}"));
    },
    CommandAttributes(category: "Bot"),
  );
}