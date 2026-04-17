import 'dart:async';

import 'package:nyxx/nyxx.dart';

typedef PrecheckData = DispatchEvent;
List<Precheck> _prechecks = [];

FutureOr<bool> fire(PrecheckData data) async {
  for (final x in _prechecks) {
    if (await x.callback.call(data) == false) {
      return false;
    }
  }

  return true;
}

class Precheck {
  final FutureOr<bool> Function(PrecheckData data) callback;
  const Precheck(this.callback);

  static void addPrecheck(Precheck check) {
    return _prechecks.add(check);
  }
}

extension GetData on DispatchEvent {
  T getData<T>(T Function(MessageComponentInteraction event) onMessageComponentInteraction, T Function(MessageCreateEvent event) onMessageCreate, T Function(ApplicationCommandInteraction event) onApplicationCommandInteraction, T Function(ApplicationCommandAutocompleteInteraction event) onApplicationCommandAutocompleteInteraction) {
    if (this is MessageComponentInteraction) return onMessageComponentInteraction.call(this as MessageComponentInteraction);
    if (this is MessageCreateEvent) return onMessageCreate.call(this as MessageCreateEvent);
    if (this is ApplicationCommandInteraction) return onApplicationCommandInteraction.call(this as ApplicationCommandInteraction);
    if (this is ApplicationCommandAutocompleteInteraction) return onApplicationCommandAutocompleteInteraction.call(this as ApplicationCommandAutocompleteInteraction);
    throw UnimplementedError("Invalid type: $runtimeType");
  }
}