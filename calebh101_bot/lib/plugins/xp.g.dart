// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'xp.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

XPLevel _$XPLevelFromJson(Map json) => XPLevel(
  requiredXp: (json['requiredXp'] as num).toInt(),
  roleId: (json['roleId'] as num).toInt(),
);

Map<String, dynamic> _$XPLevelToJson(XPLevel instance) => <String, dynamic>{
  'roleId': instance.roleId,
  'requiredXp': instance.requiredXp,
};
