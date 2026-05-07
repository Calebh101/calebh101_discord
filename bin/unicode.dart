// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const unicodeDataUrl = 'https://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt';
final outputFile = '${Directory.current.path}/lib/unicode_names.dart';

Future<void> main() async {
  print('Downloading $unicodeDataUrl ...');

  final client = HttpClient();
  final request = await client.getUrl(Uri.parse(unicodeDataUrl));
  final response = await request.close();

  if (response.statusCode != 200) {
    stderr.writeln('Failed to download: HTTP ${response.statusCode}');
    exit(1);
  }

  final lines = await response
      .transform(SystemEncoding().decoder)
      .transform(const LineSplitter())
      .toList();

  print('Download complete. Parsing ${lines.length} lines ...');

  final entries = <int, String>{};
  for (final line in lines) {
    if (line.isEmpty) continue;
    final parts = line.split(';');
    if (parts.length < 2) continue;
    final cp = int.tryParse(parts[0], radix: 16);
    if (cp == null) continue;
    final name = parts[1];
    if (name.startsWith('<')) continue;
    entries[cp] = name;
  }

  print('Writing ${entries.length} entries to $outputFile ...');
  final out = File(outputFile).openWrite();

  out.writeln('/// Get a unicode character\'s name. Auto-generated from **$unicodeDataUrl**.');
  out.write('String? getUnicodeName(int r) => _n[r];');
  out.write('const _n=<int, String>{');

  for (final cp in entries.keys.toList()..sort()) {
    final name = entries[cp]!.replaceAll("'", "\\'");
    out.write("0x${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}:'$name',");
  }

  out.write('};');
  await out.flush();
  await out.close();
  client.close();

  final size = await File(outputFile).length();
  print('Done. $outputFile: ${(size / 1024 / 1024).toStringAsFixed(1)} MB, ${entries.length} code points.');
}