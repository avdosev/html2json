import 'package:html/dom.dart' as dom;
import 'package:html/dom_parsing.dart' as dom_parser;
import 'package:html/parser.dart';
import 'dart:convert';

dynamic htmlAsParsedJson(String input) {
  final doc = parse(input);
  return prepareHtmlBlocElement(doc.body.children.first);
}

String htmlAsJson(String source) {
  return jsonEncode(htmlAsParsedJson(source));
}

const blockElements = {
  'body',
  'div',
  'details',
  'figure',
  'pre',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'figcaption',
  'p',
  'img',
  'blockquote',
  'ol',
  'ul',
};

const inlineElements = {
  'strong',
  'code',
  'em',
  'i',
  's',
  'b',
  'a',
  'um',
};

const nameToType = <String, TextMode>{
  'strong': TextMode.strong,
  'em': TextMode.emphasis,
  'i': TextMode.italic,
  's': TextMode.strikethrough,
  'b': TextMode.bold
};

Map<String, dynamic> optimizeParagraph(Map<String, dynamic> p) {
  if (p['children'].length == 1) {
    final span = p['children'][0];
    if (span['mode'].isEmpty) {
      return buildTextParagraph(span['text']);
    }
  }
  return p;
}

List<Map<String, dynamic>> prepareHtmlInlineElement(dom.Element element) {
  final children = <Map<String, dynamic>>[];

  void walk(dom.Element elem, List<TextMode> modes) {
    for (final node in elem.nodes) {
      if (node.nodeType == dom.Node.TEXT_NODE) {
        final text = node.text.replaceAll('\n', '');
        if (text.isNotEmpty) {
          children.add(buildTextSpan(text, modes: List.of(modes)));
        }
      } else if (node.nodeType == dom.Node.ELEMENT_NODE) {
        final child = node as dom.Element;
        if (nameToType.containsKey(child.localName)) {
          modes.add(nameToType[child.localName]);
          walk(child, modes);
          modes.removeLast();
        } else if (child.localName == 'a') {
          children.add(buildInlineLink(child.text, child.attributes['href']));
        } else {
          walk(child, modes);
        }
      }
    }
  }

  final defaultStyles = <TextMode>[];
  if (nameToType.containsKey(element.localName)) {
    defaultStyles.add(nameToType[element.localName]);
  } else if (element.localName == 'a') {
    return [buildInlineLink(element.text, element.attributes['href'])];
  }

  walk(element, defaultStyles);

  return children;
}

List<Map<String, dynamic>> prepareChildrenHtmlBlocElement(dom.Element element) {
  final children = <Map<String, dynamic>>[];
  var paragraph = buildDefaultParagraph();

  void makeNewParagraphAndInsertOlder() {
    if (!paragraphIsEmpty(paragraph)) {
      children.add(optimizeParagraph(paragraph));
      paragraph = buildDefaultParagraph();
    }
  }

  for (var node in element.nodes) {
    if (node.nodeType == dom.Node.TEXT_NODE) {
      final text = node.text.replaceAll('\n', '');
      if (text.isNotEmpty) {
        print('text node "$text"');
        final pch = (paragraph['children'] as List);
        // may be this branch is not popular or not active
        if (pch.isNotEmpty &&
            pch.last['type'] == 'text_span' &&
            (pch.last['mode'] as List).isEmpty) {
          pch.last.update('text', (value) => (value as String) + text);
        } else {
          pch.add(buildTextSpan(text));
        }
      }
    } else if (node.nodeType == dom.Node.ELEMENT_NODE) {
      // ignore: unnecessary_cast
      final child = node as dom.Element;
      print(child.localName);
      if (blockElements.contains(child.localName)) {
        makeNewParagraphAndInsertOlder();
        children.add(prepareHtmlBlocElement(child));
      } else if (inlineElements.contains(child.localName)) {
        if (child.localName == 'a' && !child.attributes.containsKey('href')) {
          continue;
        }
        final spans = prepareHtmlInlineElement(node);
        spans.forEach((span) => addSpanToParagraph(paragraph, span));
      } else if (child.localName == 'br') {
        makeNewParagraphAndInsertOlder();
      } else {
        print('Not found case for ${child.localName}');
      }
    }
  }

  makeNewParagraphAndInsertOlder();

  return children;
}

Map<String, dynamic> prepareHtmlBlocElement(dom.Element element) {
  switch (element.localName) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      return buildHeadLine(element.text, element.localName);
    case 'figcaption':
      final p = buildDefaultParagraph();
      addSpanToParagraph(p, prepareHtmlInlineElement(element));
      return p;
    case 'p':
      final p = buildDefaultParagraph();
      addSpanToParagraph(p, prepareHtmlInlineElement(element));
      return p;
    case 'code':
      final code = element.text;
      return buildCode(
        code,
        element.classes.toList()..removeWhere((element) => element == 'hljs'),
      );
    case 'img':
      final url = element.attributes['data-src'] ?? element.attributes['src'];
      return buildImage(url);
      break;
    case 'blockquote':
      return buildBlockQuote(prepareChildrenHtmlBlocElement(element));
    case 'ol':
    case 'ul':
      final type =
          element.localName == 'ol' ? ListType.ordered : ListType.unordered;
      return buildList(type,
          element.children.map((li) => prepareHtmlBlocElement(li)).toList());
      break;
    case 'body':
    case 'div':
    case 'li':
      if (element.classes.contains('spoiler')) {
        return buildDetails(
          element.getElementsByClassName('spoiler_title')[0].text,
          prepareHtmlBlocElement(
              element.getElementsByClassName('spoiler_text')[0]),
        );
      } else {
        return buildDiv(prepareChildrenHtmlBlocElement(element));
      }
      break;
    case 'details':
      return buildDetails(
        element.children[0].text,
        prepareHtmlBlocElement(element.children[1]),
      );
    case 'figure':
      final img = element.getElementsByTagName('img')[0];
      final caption = element.getElementsByTagName('figcaption')[0];
      final imgBloc = prepareHtmlBlocElement(img);
      addCaption(imgBloc, caption.text);
      return imgBloc;
    case 'pre':
      return buildPre(prepareHtmlBlocElement(element.children.first));
    default:
      print('Not found case for ${element.localName}');
      throw UnsupportedError('${element.localName} not supported');
  }
}

Map<String, dynamic> buildWithChildren(String type, List<dynamic> children) =>
    {'type': type, 'children': children};

Map<String, dynamic> buildWithChild(String type, dynamic child) =>
    {'type': type, 'child': child};

enum TextMode {
  bold,
  italic,
  emphasis,
  underline,
  strikethrough,
  anchor,
  strong
}

enum ListType { unordered, ordered }

Map<String, dynamic> buildDefaultParagraph() =>
    {'type': 'paragraph', 'children': []};

void addSpanToParagraph(p, span) {
  final pch = (p['children'] as List);
  pch.add(span);
}

bool paragraphIsEmpty(p) {
  return p['children'].isEmpty;
}

Map<String, dynamic> buildTextParagraph(String text) => {
      'type': 'tp',
      'text': text,
    };

Map<String, dynamic> buildTextSpan(String text,
        {List<TextMode> modes = const []}) =>
    {
      'type': 'span',
      'text': text,
      'mode': modes.map((mode) => mode.toString()).toList(),
    };

Map<String, dynamic> buildHeadLine(String text, String headline) => {
      'type': 'hl',
      'text': text,
      'mode': headline,
    };

Map<String, dynamic> buildImage(String src) => {
      'type': 'image',
      'src': src,
    };

Map<String, dynamic> buildCode(String text, List<String> language) =>
    {'type': 'code', 'text': text, 'language': language};

void addCaption(image, String caption) {
  image['caption'] = caption;
}

Map<String, dynamic> buildList(ListType listType, List<dynamic> children) =>
    buildWithChildren(
        listType.toString().substring('ListType'.length + 1) + '_list',
        children);

Map<String, dynamic> buildDetails(String title, child) =>
    {'type': 'details', 'child': child, 'title': title};

Map<String, dynamic> buildPre(dynamic child) => buildWithChild('pre', child);

Map<String, dynamic> buildDiv(List<dynamic> children) =>
    buildWithChildren('division', children);

Map<String, dynamic> buildBlockQuote(List<dynamic> children) =>
    buildWithChildren('blockquote', children);

Map<String, dynamic> buildInlineLink(String text, String src) =>
    {'type': 'link_span', 'text': text, 'src': src};
