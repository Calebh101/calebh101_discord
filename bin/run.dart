import 'dart:io';

import 'package:calebh101_discord/calebh101_discord.dart';

const int maxCrashes = 20;
const Duration crashResetTimer = Duration(minutes: 30);

int crashes = 0;

Future<void> main(List<String> arguments) async {
  Logger.print("Runner", "Starting runner...");

  () async {
    // Every X minutes, reset our crash count to 0. So if we crashed 19 times over the last 5 years, it doesn't build up.
    await Future.delayed(crashResetTimer);
    Logger.print("Runner", "Resetting crashes to 0, was $crashes");
    crashes = 0;
  }();

  while (true) {
    final process = await Process.start(
      "dart", ["run", "bin/main.dart", ...arguments],
      mode: ProcessStartMode.inheritStdio,
    );

    // This waits for the process to stop.
    final code = await process.exitCode;
    Logger.print("Runner", "Process exited with exit code $code.");

    switch (code) {
      case ExitCode.success:
        exit(0);
      case ExitCode.restart:
        Logger.print("Runner", "Restarting...");
        await Future.delayed(Duration(milliseconds: 250));
        continue;
    }

    if (++crashes >= maxCrashes) {
      Logger.error("Runner", "Process has crashed $crashes times too quickly. The process will not be restarted.");
      exit(1);
    }

    Logger.error("Runner", "Invalid exit code: $code. Process has crashed $crashes times. The process will be restarted.");
    await Future.delayed(Duration(seconds: 5));
  }
}
