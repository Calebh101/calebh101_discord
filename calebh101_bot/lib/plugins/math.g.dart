// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'math.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddSubtractMath _$AddSubtractMathFromJson(Map json) => AddSubtractMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
      symbol: $enumDecode(_$SymbolEnumMap, json['symbol']),
    );

Map<String, dynamic> _$AddSubtractMathToJson(AddSubtractMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
      'symbol': _$SymbolEnumMap[instance.symbol]!,
    };

const _$SymbolEnumMap = {
  Symbol.add: 'add',
  Symbol.subtract: 'subtract',
  Symbol.multiply: 'multiply',
  Symbol.divide: 'divide',
};

MultDivMath _$MultDivMathFromJson(Map json) => MultDivMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
      symbol: $enumDecode(_$SymbolEnumMap, json['symbol']),
    );

Map<String, dynamic> _$MultDivMathToJson(MultDivMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
      'symbol': _$SymbolEnumMap[instance.symbol]!,
    };

ExponentMath _$ExponentMathFromJson(Map json) => ExponentMath(
      a: (json['a'] as num).toInt(),
      b: (json['b'] as num).toInt(),
      result: (json['result'] as num).toInt(),
    );

Map<String, dynamic> _$ExponentMathToJson(ExponentMath instance) =>
    <String, dynamic>{
      'result': instance.result,
      'a': instance.a,
      'b': instance.b,
    };
