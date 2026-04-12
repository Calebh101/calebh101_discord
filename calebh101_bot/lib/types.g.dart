// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'types.dart';

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

Math _$MathFromJson(Map json) => Math(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
      operand: $enumDecode(_$OperandEnumMap, json['operand']),
    );

Map<String, dynamic> _$MathToJson(Math instance) => <String, dynamic>{
      'a': instance.a,
      'b': instance.b,
      'result': instance.result,
      'operand': _$OperandEnumMap[instance.operand]!,
    };

const _$OperandEnumMap = {
  Operand.add: 'add',
  Operand.subtract: 'subtract',
  Operand.multiply: 'multiply',
  Operand.divide: 'divide',
};
