import 'dart:async';

import 'package:nyxx/nyxx.dart';

final class NyxxCommandsPlugin extends NyxxPlugin<NyxxGateway> {
  @override
  FutureOr<void> afterConnect(NyxxGateway client) {
    client.onApplicationCommandInteraction.listen((event) async {
      final interaction = event.interaction;
      final data = interaction.data;
    });
  }
}