import 'dart:io';
import 'package:html_to_json/html_to_json.dart';

void main(List<String> arguments) async {
  if (arguments.length < 2) {
    print('need count args more then two');
    print('html2json [src] [dst]');
    return;
  }
  final src = arguments[0];
  final dst = arguments[1];
  final data = await File(src).readAsString();
  final result = htmlAsJson(data);
  await (File(dst)..createSync()).writeAsString(result);
}
