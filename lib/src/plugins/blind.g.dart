// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blind.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Blind _$BlindFromJson(Map json) => Blind(
  reason: json['reason'] as String?,
  time: json['time'] == null ? null : DateTime.parse(json['time'] as String),
  id: (json['id'] as num).toInt(),
  user: (json['user'] as num).toInt(),
  client: (json['client'] as num).toInt(),
);

Map<String, dynamic> _$BlindToJson(Blind instance) => <String, dynamic>{
  'reason': instance.reason,
  'time': instance.time?.toIso8601String(),
  'id': instance.id,
  'user': instance.user,
  'client': instance.client,
};
