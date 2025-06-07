import 'dart:convert';
import 'dart:io';

import 'package:example/src/platform_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

void main() {
  runApp(MyApp());
}

bool get isDesktop {
  if (kIsWeb) return false;
  return [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  ].contains(defaultTargetPlatform);
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xterm.dart demo',
      debugShowCheckedModeBanner: false,
      home: AppPlatformMenu(child: Home()),
      // shortcuts: ,
    );
  }
}

class Home extends StatefulWidget {
  Home({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  final terminal = Terminal(
    maxLines: 10000,
  );

  late final terminalController = TerminalController(vsync: this);

  late final Pty pty;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.endOfFrame.then(
      (_) {
        if (mounted) _startPty();
      },
    );
  }

  void _startPty() {
    pty = Pty.start(
      shell,
      columns: terminal.viewWidth,
      rows: terminal.viewHeight,
    );

    pty.output
        .cast<List<int>>()
        .transform(Utf8Decoder())
        .listen(terminal.write);

    /// It's better for debugging the [CellOffset]
    for (var i = 1; i < 70; i++) {
      terminal.write('$i');
      final iWidth = i.toString().length;
      terminal.write(' ');
      for (var j = iWidth + 1; j < terminal.viewWidth; j++) {
        final surplus = j % 10;
        if (surplus == 0) {
          terminal.write(' ');
          continue;
        }
        terminal.write('$surplus');
      }
    }

    pty.exitCode.then((code) {
      terminal.write('the process exited with exit code $code');
    });

    terminal.onOutput = (data) {
      pty.write(const Utf8Encoder().convert(data));
    };

    terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              color: Colors.yellow,
              child: Center(
                child: Text(
                  'xterm.dart demo',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
            ),
            _buildTerm,
          ],
        ),
      ),
    );
  }

  Widget get _buildTerm {
    return TerminalView(
          terminal,
          controller: terminalController,
          autofocus: true,
          backgroundOpacity: 0.7,
          theme: TerminalTheme(
            cursor: Color(0XAAAEAFAD),
            selectionCursor: Color.fromARGB(255, 139, 34, 81),
            selection: Color(0XAAAEAFAD),
            foreground: Color(0XFFCCCCCC),
            background: Color.fromARGB(255, 0, 0, 0),
            black: Color(0XFF000000),
            red: Color(0XFFCD3131),
            green: Color(0XFF0DBC79),
            yellow: Color(0XFFE5E510),
            blue: Color(0XFF2472C8),
            magenta: Color(0XFFBC3FBC),
            cyan: Color(0XFF11A8CD),
            white: Color(0XFFE5E5E5),
            brightBlack: Color(0XFF666666),
            brightRed: Color(0XFFF14C4C),
            brightGreen: Color(0XFF23D18B),
            brightYellow: Color(0XFFF5F543),
            brightBlue: Color(0XFF3B8EEA),
            brightMagenta: Color(0XFFD670D6),
            brightCyan: Color(0XFF29B8DB),
            brightWhite: Color(0XFFFFFFFF),
            searchHitBackground: Color(0XFFFFFF2B),
            searchHitBackgroundCurrent: Color(0XFF31FF26),
            searchHitForeground: Color(0XFF000000),
          ),
          onSecondaryTapDown: (details, offset) async {
            final selection = terminalController.selection;
            if (selection != null) {
              final text = terminal.buffer.getText(selection);
              terminalController.clearSelection();
              await Clipboard.setData(ClipboardData(text: text));
            } else {
              final data = await Clipboard.getData('text/plain');
              final text = data?.text;
              if (text != null) {
                terminal.paste(text);
              }
            }
          },
        );
  }
}

String get shell {
  if (Platform.isMacOS || Platform.isLinux) {
    return Platform.environment['SHELL'] ?? 'bash';
  }

  if (Platform.isWindows) {
    return 'cmd.exe';
  }

  return 'sh';
}
