// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'math.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddSubtractMath _$AddSubtractMathFromJson(Map json) => AddSubtractMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
      operand: $enumDecode(_$OperandEnumMap, json['operand']),
    );

Map<String, dynamic> _$AddSubtractMathToJson(AddSubtractMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
      'operand': _$OperandEnumMap[instance.operand]!,
    };

const _$OperandEnumMap = {
  Operand.add: 'add',
  Operand.subtract: 'subtract',
  Operand.multiply: 'multiply',
  Operand.divide: 'divide',
};

MultDivMath _$MultDivMathFromJson(Map json) => MultDivMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
      operand: $enumDecode(_$OperandEnumMap, json['operand']),
    );

Map<String, dynamic> _$MultDivMathToJson(MultDivMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
      'operand': _$OperandEnumMap[instance.operand]!,
    };

SquareMath _$SquareMathFromJson(Map json) => SquareMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
    );

Map<String, dynamic> _$SquareMathToJson(SquareMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
    };
