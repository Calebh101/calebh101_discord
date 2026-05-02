// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'moderation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Warn _$WarnFromJson(Map json) => Warn(
  timestamp: DateTime.parse(json['timestamp'] as String),
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$WarnToJson(Warn instance) => <String, dynamic>{
  'reason': instance.reason,
  'timestamp': instance.timestamp.toIso8601String(),
};
