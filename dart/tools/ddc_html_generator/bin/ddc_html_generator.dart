import 'dart:io';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:html/parser_console.dart';
import 'package:args/args.dart';
import 'package:path/path.dart' as path;

main(args) {
  var options = _parseOptions(args);
  Document document;
  if (options.htmlInput != null) {
    useConsole();
    var file = new File(options.htmlInput).openSync();
    document = parse(file, encoding: 'utf8');
    file.closeSync();
    for (var tag in document.querySelectorAll('script')) {
      var src = tag.attributes['src'];
      if (tag.attributes['type'] == 'application/dart' ||
          (src != null && src.endsWith('/browser/dart.js'))) {
        tag.remove();
      }
    }
  } else {
    document = parse('<!DOCTYPE html><html><head><body>');
  }

  document.head.nodes.insert(0, parseFragment(headScripts(options)));
  document.body.nodes.add(parseFragment(loadScript(options)));

  new File(options.out).writeAsStringSync(document.outerHtml);
}

class _Options {
  final String ddcRuntimePrefix;
  final String script;
  final String entryModule;
  final String entryLibrary;
  final bool includeTest;
  final String htmlInput;
  final String out;
  _Options(this.ddcRuntimePrefix, this.script, this.entryModule,
      String entryLibrary, this.includeTest, this.htmlInput, this.out)
      : entryLibrary = escapeAsIdentifier(entryLibrary);
}

_Options _parseOptions(args) {
  var parser = new ArgParser()
    ..addOption('ddc_runtime_prefix',
        help: 'prefix to apply to the ddc runtime file paths')
    ..addOption('script',
        help: 'path to the generated .js file with all of'
            ' the code generated by DDC')
    ..addOption('entry_module',
        help: 'name of the module containing the'
            ' main method of the program')
    ..addOption('entry_library',
        help: '(unescaped) name of the library '
            ' containing the main method of the program')
    ..addFlag('include_test',
        defaultsTo: false,
        help: 'whether the app is a test that uses package:test and therefore '
            'needs the "packages/test/dart.js" file loaded in the HTML.')
    ..addOption('input_html',
        help: 'start from the existing HTML file'
            ' instead of creating a blank HTML page')
    ..addOption('out',
        abbr: 'o',
        help: 'output location for the '
            'generated HTML')
    ..addFlag('help',
        defaultsTo: false, abbr: 'h', help: 'show this usage message.');
  var data;
  try {
    data = parser.parse(args);
  } catch (e) {
    print(e.message);
    print(parser.usage);
    exit(1);
  }
  if (data['help']) {
    print('ddc_html_generator usage:');
    print(parser.usage);
    exit(0);
  }
  var requriedArgs = [
    'ddc_runtime_prefix',
    'script',
    'entry_module',
    'entry_library',
    'out'
  ];
  for (var name in requriedArgs) {
    if (data[name] == null) {
      print('ddc_html_generator tool: $name option is missing.');
      print(parser.usage);
      exit(1);
    }
  }
  return new _Options(
      data['ddc_runtime_prefix'],
      data['script'],
      data['entry_module'],
      data['entry_library'],
      data['include_test'],
      data['input_html'],
      data['out']);
}

String headScripts(_Options options) {
  var sb = new StringBuffer();
  addScript(url, {bool defer: true}) {
    sb.write('\n  <script src="$url"');
    if (defer) sb.write(' defer');
    sb.write('></script>');
  }

  addScript('${options.ddcRuntimePrefix}dart_library.js');
  addScript('${options.ddcRuntimePrefix}dart_sdk.js');

  if (options.includeTest) {
    // TODO: Remove this hack, package:test requires both of these
    // things to exist in precompiled mode, but it really shouldn't. Need to
    // first figure out how to properly load packages/test/dart.js in order for
    // it to work this way.
    var script = options.script.replaceFirst('.browser_test.dart.js', '');
    sb.write('\n  <link rel="x-dart-test" href="$script">');
    addScript('packages/test/dart.js', defer: false);
  }

  // TODO: Don't include this if options.includeTest is true, once we
  // get that working properly.
  addScript('${options.script}');
  return '$sb';
}

String loadScript(_Options options) => '''
\n  <script>
    document.addEventListener("DOMContentLoaded", function(event) {
      dart_library.start("${options.entryModule}", "${options.entryLibrary}");
    });
  </script>
''';

// TODO(sigmund): this was copied from DDC, ideally we shoud share this code.

/// Escape [name] to make it into a valid identifier.
String escapeAsIdentifier(String name) {
  name = path.basenameWithoutExtension(name);
  if (name.length == 0) return r'$';

  // Escape any invalid characters
  StringBuffer buffer = null;
  for (int i = 0; i < name.length; i++) {
    var ch = name[i];
    var needsEscape = ch == r'$' || _invalidCharInIdentifier.hasMatch(ch);
    if (needsEscape && buffer == null) {
      buffer = new StringBuffer(name.substring(0, i));
    }
    if (buffer != null) {
      buffer.write(needsEscape ? '\$${ch.codeUnits.join("")}' : ch);
    }
  }

  var result = buffer != null ? '$buffer' : name;
  // Ensure the identifier first character is not numeric and that the whole
  // identifier is not a keyword.
  if (result.startsWith(new RegExp('[0-9]')) || invalidVariableName(result)) {
    return '\$$result';
  }
  return result;
}

// Invalid characters for identifiers, which would need to be escaped.
final _invalidCharInIdentifier = new RegExp(r'[^A-Za-z_$0-9]');

/// Returns true for invalid JS variable names, such as keywords.
/// Also handles invalid variable names in strict mode, like "arguments".
bool invalidVariableName(String keyword, {bool strictMode: true}) {
  switch (keyword) {
    // http://www.ecma-international.org/ecma-262/6.0/#sec-future-reserved-words
    case "await":

    case "break":
    case "case":
    case "catch":
    case "class":
    case "const":
    case "continue":
    case "debugger":
    case "default":
    case "delete":
    case "do":
    case "else":
    case "enum":
    case "export":
    case "extends":
    case "finally":
    case "for":
    case "function":
    case "if":
    case "import":
    case "in":
    case "instanceof":
    case "let":
    case "new":
    case "return":
    case "super":
    case "switch":
    case "this":
    case "throw":
    case "try":
    case "typeof":
    case "var":
    case "void":
    case "while":
    case "with":
      return true;
    case "arguments":
    case "eval":
    // http://www.ecma-international.org/ecma-262/6.0/#sec-future-reserved-words
    // http://www.ecma-international.org/ecma-262/6.0/#sec-identifiers-static-semantics-early-errors
    case "implements":
    case "interface":
    case "let":
    case "package":
    case "private":
    case "protected":
    case "public":
    case "static":
    case "yield":
      return strictMode;
  }
  return false;
}