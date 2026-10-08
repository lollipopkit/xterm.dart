import 'dart:convert';

import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

String b64(String text) => base64.encode(utf8.encode(text));

ProgramStatusReport? parse(String payload) =>
    ProgramStatusReport.parse([payload]);

void main() {
  group('ProgramStatusReport.parse', () {
    test('reads every key', () {
      final report = parse(
        'state=blocked:kind=permission:progress=40:app=terraform:'
        'id=deploy/us-east:title=${b64('US East')}:msg=${b64('Apply 3?')}',
      )!;
      expect(report.state, ProgramState.blocked);
      expect(report.kind, ProgramBlockKind.permission);
      expect(report.progress, 40);
      expect(report.app, 'terraform');
      expect(report.id, ['deploy', 'us-east']);
      expect(report.title, 'US East');
      expect(report.msg, 'Apply 3?');
    });

    test('requires a known state', () {
      expect(parse('app=x'), isNull);
      expect(parse('state=busy'), isNull);
      expect(parse('state=clear')!.isClear, isTrue);
    });

    test('skips malformed pairs, ignores unknown keys, last value wins', () {
      final report = parse('junk:=x:state=idle:foo=bar:state=done:a b=c')!;
      expect(report.state, ProgramState.done);
    });

    test('refuses a key longer than 16 bytes', () {
      expect(parse('state=idle:abcdefghijklmnopq=1'), isNull);
      expect(parse('state=idle:abcdefghijklmnop=1'), isNotNull);
    });

    test('refuses a malformed id', () {
      expect(parse('state=idle:id=a//b'), isNull);
      expect(parse('state=idle:id=${'a' * 33}'), isNull);
      expect(parse('state=idle:id=${List.filled(9, 'a').join('/')}'), isNull);
      expect(parse('state=idle:id=${List.filled(8, 'a').join('/')}'), isNotNull);
      expect(parse('state=idle:id=a,b'), isNull);
    });

    test('keeps kind and progress only where they apply', () {
      final done = parse('state=done:kind=auth:progress=10')!;
      expect(done.kind, isNull);
      expect(done.progress, isNull);
      expect(parse('state=working:progress=101')!.progress, isNull);
      expect(parse('state=blocked:kind=nope')!.kind, isNull);
    });

    test('accepts base64 without padding', () {
      expect(parse('state=done:msg=aGk')!.msg, 'hi');
    });

    test('refuses decoded control characters', () {
      expect(parse('state=done:msg=${b64('a\nb')}'), isNull);
      expect(parse('state=done:title=${b64('a\u009bb')}'), isNull);
    });

    test('strips invisible formatting from text', () {
      expect(parse('state=done:msg=${b64('a\u202Eb\u200Bc')}')!.msg, 'abc');
    });

    test('enforces size caps', () {
      expect(parse('state=done:msg=${b64('a' * 2048)}'), isNotNull);
      expect(parse('state=done:msg=${b64('a' * 2049)}'), isNull);
      expect(parse('state=done:title=${b64('a' * 193)}'), isNull);
      expect(parse('state=done:app=${'a' * 33}'), isNull);
      expect(parse('state=done:x=${'a' * 4100}'), isNull);
      // 1400 three-byte characters: under 4096 UTF-16 units, over in bytes.
      expect(parse('state=done:x=${'界' * 1400}'), isNull);
      expect(parse('state=done:x=${'界' * 1000}'), isNotNull);
    });

    test('a report is one argument', () {
      expect(ProgramStatusReport.parse(['state=done', 'x']), isNull);
    });
  });

  test('sameAs compares id by segment', () {
    const a = ProgramStatusReport(state: ProgramState.done, id: ['a/b']);
    const b = ProgramStatusReport(state: ProgramState.done, id: ['a', 'b']);
    expect(a.sameAs(b), isFalse);
    expect(b.sameAs(const ProgramStatusReport(state: ProgramState.done, id: ['a', 'b'])), isTrue);
  });

  group('TerminalProgress.parse', () {
    test('maps OSC 9;4 states', () {
      expect(TerminalProgress.parse(['4', '0'])!.state, isNull);
      expect(TerminalProgress.parse(['4', '1', '50'])!.percent, 50);
      expect(
        TerminalProgress.parse(['4', '2'])!.state,
        TerminalProgressState.error,
      );
      expect(
        TerminalProgress.parse(['4', '3', '20'])!.percent,
        isNull,
      );
      expect(TerminalProgress.parse(['4', '1', '250'])!.percent, 100);
      expect(TerminalProgress.parse(['4', '9']), isNull);
      expect(TerminalProgress.parse(['hello']), isNull);
    });
  });

  group('ShellMark.parse', () {
    test('reads the mark and exit code', () {
      expect(ShellMark.parse(['A', 'special_key=1'])!.kind,
          ShellMarkKind.promptStart);
      expect(ShellMark.parse(['D', '2'])!.exitCode, 2);
      expect(ShellMark.parse(['D'])!.exitCode, isNull);
      expect(ShellMark.parse(['P']), isNull);
    });
  });

  group('ProgramStatusRecords', () {
    ProgramStatusReport report(String payload) => parse(payload)!;

    test('a report replaces its record whole', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=working:msg=${b64('a')}:app=x'))
        ..apply(report('state=done'));
      expect(records.records.single.report.msg, isNull);
      expect(records.records.single.report.app, isNull);
    });

    test('clear removes the record and its descendants', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=working'))
        ..apply(report('state=working:id=a'))
        ..apply(report('state=blocked:id=a/b'))
        ..apply(report('state=done:id=ab'))
        ..apply(report('state=clear:id=a'));
      expect(records.records.map((r) => r.key), ['', 'ab']);
      records.apply(report('state=clear'));
      expect(records.records, isEmpty);
    });

    test('app is inherited from the nearest ancestor naming one', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=working:app=deploy'))
        ..apply(report('state=working:id=a/b'));
      expect(records.appOf(records[['a', 'b']]!), 'deploy');
    });

    test('evicts the least recently reported record', () {
      final records = ProgramStatusRecords(maxRecords: 2)
        ..apply(report('state=idle:id=a'))
        ..apply(report('state=idle:id=b'))
        ..apply(report('state=idle:id=a'))
        ..apply(report('state=idle:id=c'));
      expect(records.records.map((r) => r.key), ['a', 'c']);
    });

    test('a prompt or exit drops what only lasts while running', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=working:id=w'))
        ..apply(report('state=blocked:id=b'))
        ..apply(report('state=idle:id=i'))
        ..apply(report('state=done:id=d'))
        ..apply(report('state=error:id=e'))
        ..apply(const TerminalProgress(TerminalProgressState.normal, 5))
        ..apply(const ShellMark(ShellMarkKind.promptStart));
      expect(records.records.map((r) => r.key), ['d', 'e']);
      expect(records.progress, isNull);

      records
        ..apply(report('state=working'))
        ..apply(const TerminalProgress(TerminalProgressState.error))
        ..processExited();
      expect(records.records.map((r) => r.key), ['d', 'e']);
      expect(records.progress?.state, TerminalProgressState.error);
    });

    test('state is the most urgent one', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=working'))
        ..apply(report('state=done:id=a'));
      expect(records.state, ProgramState.done);
      records.apply(report('state=blocked:id=b'));
      expect(records.state, ProgramState.blocked);
      final progress = ProgramStatusRecords()
        ..apply(const TerminalProgress(TerminalProgressState.indeterminate));
      expect(progress.state, ProgramState.working);
    });

    test('tracks the shell command', () {
      final records = ProgramStatusRecords()
        ..apply(const ShellMark(ShellMarkKind.commandExecuted));
      expect(records.command!.running, isTrue);
      records.apply(const ShellMark(ShellMarkKind.commandFinished, exitCode: 1));
      expect(records.command!.failed, isTrue);
    });

    test('a full reset removes everything', () {
      final records = ProgramStatusRecords()
        ..apply(report('state=done'))
        ..apply(const TerminalProgress(TerminalProgressState.error))
        ..apply(const TerminalStatusReset());
      expect(records.isEmpty, isTrue);
    });

    test('notifies only on change', () {
      var count = 0;
      final records = ProgramStatusRecords()..addListener(() => count++);
      records
        ..apply(report('state=clear'))
        ..apply(const ShellMark(ShellMarkKind.promptStart))
        ..apply(report('state=done'))
        ..apply(report('state=done'))
        ..apply(const TerminalProgress(TerminalProgressState.normal, 5))
        ..apply(const TerminalProgress(TerminalProgressState.normal, 5))
        ..apply(const ShellMark(ShellMarkKind.commandExecuted))
        ..apply(const ShellMark(ShellMarkKind.commandExecuted))
        ..apply(const ShellMark(ShellMarkKind.commandFinished, exitCode: 1))
        ..apply(const ShellMark(ShellMarkKind.commandFinished, exitCode: 1));
      expect(count, 4);

      // The same report from another record first is a change of order.
      records
        ..apply(report('state=done:id=a'))
        ..apply(report('state=done'));
      expect(records.records.map((r) => r.key), ['a', '']);
      expect(count, 6);
    });
  });

  group('Terminal', () {
    test('emits status events and keeps other OSCs private', () {
      final events = <TerminalStatusEvent>[];
      final private = <String>[];
      final terminal = Terminal(
        onStatus: events.add,
        onPrivateOSC: (code, args) => private.add('$code;${args.join(';')}'),
      );
      terminal.write('\x1b]7501;state=working:app=cargo\x1b\\');
      terminal.write('\x1b]7501;state=bogus\x07');
      terminal.write('\x1b]9;4;1;30\x07');
      terminal.write('\x1b]9;hello\x07');
      terminal.write('\x1b]133;D;0\x1b\\');
      terminal.write('\x1bc');
      expect(events.map((e) => e.runtimeType), [
        ProgramStatusReport,
        TerminalProgress,
        ShellMark,
        TerminalStatusReset,
      ]);
      expect(private, ['9;hello']);
    });

    test('answers the query only while status is read', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);
      terminal.write('\x1b]7501;?\x1b\\');
      expect(output, isEmpty);
      terminal.onStatus = (_) {};
      terminal.write('\x1b]7501;?\x07');
      expect(output, ['\x1b]7501;?\x1b\\']);
    });

    test('a soft reset keeps records', () {
      final events = <TerminalStatusEvent>[];
      Terminal(onStatus: events.add).write('\x1b[!p');
      expect(events, isEmpty);
    });
  });
}
