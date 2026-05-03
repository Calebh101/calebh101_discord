// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mute.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Mute _$MuteFromJson(Map json) => Mute(
  reason: json['reason'] as String?,
  time: DateTime.parse(json['time'] as String),
  id: (json['id'] as num).toInt(),
  user: (json['user'] as num).toInt(),
  client: (json['client'] as num).toInt(),
);

Map<String, dynamic> _$MuteToJson(Mute instance) => <String, dynamic>{
  'reason': instance.reason,
  'time': instance.time.toIso8601String(),
  'id': instance.id,
  'user': instance.user,
  'client': instance.client,
};
