import 'dart:convert';

import 'package:collection/collection.dart';

import 'package:xterm/src/base/observable.dart';

/// What a program reports about itself, from the most to the least urgent.
///
/// See the Program Status Protocol (OSC 7501):
/// https://gist.github.com/mitchellh/7acae3abd8355c1c00287d67e96c913a
enum ProgramState {
  /// Can't continue until the user does something.
  blocked,

  /// Failed and stopped.
  error,

  /// Finished; the result is ready and the user hasn't seen it yet.
  done,

  /// Running.
  working,

  /// At rest, waiting for the user's next instruction.
  idle;

  /// Whether this state survives the program's exit and a new shell prompt.
  bool get persists => this == done || this == error;
}

/// What a `blocked` program waits for.
enum ProgramBlockKind { permission, question, auth }

/// Something a program told the terminal about its state, or that the terminal
/// itself did to that state. Parsed by [EscapeParser], emitted by
/// [Terminal.onStatus], kept by [ProgramStatusRecords].
sealed class TerminalStatusEvent {
  const TerminalStatusEvent();

  /// Parses an OSC that carries status, or returns null when [code] / [args]
  /// is no such report or a malformed one. A program status query
  /// (`OSC 7501 ; ?`) is not an event: see [ProgramStatusReport.isQuery].
  static TerminalStatusEvent? fromOsc(String code, List<String> args) {
    return switch (code) {
      ProgramStatusReport.oscCode => ProgramStatusReport.parse(args),
      TerminalProgress.oscCode => TerminalProgress.parse(args),
      ShellMark.oscCode => ShellMark.parse(args),
      _ => null,
    };
  }
}

/// A report of the Program Status Protocol, `OSC 7501 ; pairs ST`.
final class ProgramStatusReport extends TerminalStatusEvent {
  const ProgramStatusReport({
    required this.state,
    this.id = const [],
    this.kind,
    this.progress,
    this.app,
    this.title,
    this.msg,
  });

  /// A report removing [id] and its descendants, or every record when [id] is
  /// empty.
  const ProgramStatusReport.clear({this.id = const []})
    : state = null,
      kind = null,
      progress = null,
      app = null,
      title = null,
      msg = null;

  static const oscCode = '7501';

  /// The whole sequence, `OSC` through `ST`.
  static const maxSequenceBytes = 4096;

  /// `ESC ] 7501 ;` and `ESC \`.
  static const _framingBytes = 9;
  static const _maxKeyBytes = 16;
  static const _maxMsgEncodedBytes = 2732;
  static const _maxMsgBytes = 2048;
  static const _maxTitleEncodedBytes = 256;
  static const _maxTitleBytes = 192;
  static const _maxNameBytes = 32;
  static const _maxIdBytes = 128;
  static const _maxIdDepth = 8;

  static final _key = RegExp(r'^[a-z]+$');
  static final _value = RegExp(r'^[A-Za-z0-9_.,+/=-]*$');
  static final _name = RegExp(r'^[A-Za-z0-9_.+-]{1,32}$');
  static final _percent = RegExp(r'^[0-9]{1,3}$');

  /// Null for `state=clear`.
  final ProgramState? state;

  /// The record's path; empty for the root record.
  final List<String> id;

  /// Only with [ProgramState.blocked].
  final ProgramBlockKind? kind;

  /// 0–100, only with [ProgramState.working] or [ProgramState.blocked]; null
  /// is indeterminate.
  final int? progress;

  /// The program, as given in this report; see [ProgramStatusRecords.appOf]
  /// for the inherited one.
  final String? app;

  /// A short label, decoded and safe to display as plain text.
  final String? title;

  /// One line on what is going on, decoded and safe to display as plain text.
  final String? msg;

  bool get isClear => state == null;

  /// Whether [other] says exactly what this does.
  bool sameAs(ProgramStatusReport other) =>
      state == other.state &&
      kind == other.kind &&
      progress == other.progress &&
      app == other.app &&
      title == other.title &&
      msg == other.msg &&
      const ListEquality<String>().equals(id, other.id);

  /// Whether [args] (after `7501`) is the support query, `OSC 7501 ; ? ST`.
  static bool isQuery(List<String> args) => args.length == 1 && args[0] == '?';

  /// Parses the payload after `7501;`, or returns null when the spec says to
  /// refuse the whole report.
  static ProgramStatusReport? parse(List<String> args) {
    // `;` is not in the value alphabet, so a report is exactly one argument.
    if (args.length != 1) return null;
    final payload = args[0];
    // Bytes, not UTF-16 units: a malformed pair is skipped rather than
    // refused, so the payload can carry text outside the value alphabet.
    if (payload.length + _framingBytes > maxSequenceBytes ||
        utf8.encode(payload).length + _framingBytes > maxSequenceBytes) {
      return null;
    }

    final pairs = <String, String>{};
    for (final pair in payload.split(':')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = pair.substring(0, eq);
      final value = pair.substring(eq + 1);
      if (!_key.hasMatch(key) || !_value.hasMatch(value)) continue;
      if (key.length > _maxKeyBytes) return null;
      pairs[key] = value;
    }

    final stateName = pairs['state'];
    if (stateName == null) return null;
    final ProgramState? state;
    if (stateName == 'clear') {
      state = null;
    } else {
      state = ProgramState.values.asNameMap()[stateName];
      if (state == null) return null;
    }

    final rawId = pairs['id'];
    final id = rawId == null ? const <String>[] : _parseId(rawId);
    if (id == null) return null;
    if (state == null) return ProgramStatusReport.clear(id: id);

    final app = pairs['app'];
    if (app != null && app.length > _maxNameBytes) return null;

    final title = _decodeText(
      pairs['title'],
      _maxTitleEncodedBytes,
      _maxTitleBytes,
    );
    final msg = _decodeText(pairs['msg'], _maxMsgEncodedBytes, _maxMsgBytes);
    if (title is _Refused || msg is _Refused) return null;

    final kindName = pairs['kind'];
    final rawProgress = pairs['progress'];
    final percent = rawProgress != null && _percent.hasMatch(rawProgress)
        ? int.parse(rawProgress)
        : null;

    return ProgramStatusReport(
      state: state,
      id: id,
      kind: state == ProgramState.blocked && kindName != null
          ? ProgramBlockKind.values.asNameMap()[kindName]
          : null,
      progress:
          (state == ProgramState.working || state == ProgramState.blocked) &&
              percent != null &&
              percent <= 100
          ? percent
          : null,
      app: app != null && _name.hasMatch(app) ? app : null,
      title: title is _Text ? title.text : null,
      msg: msg is _Text ? msg.text : null,
    );
  }

  static List<String>? _parseId(String raw) {
    if (raw.length > _maxIdBytes) return null;
    final segments = raw.split('/');
    if (segments.length > _maxIdDepth) return null;
    for (final segment in segments) {
      if (!_name.hasMatch(segment)) return null;
    }
    return List.unmodifiable(segments);
  }

  /// Null when absent or unusable (the key is then ignored), [_Refused] when
  /// the whole report must be refused.
  static _Decoded? _decodeText(String? raw, int maxEncoded, int maxDecoded) {
    if (raw == null) return null;
    if (raw.length > maxEncoded) return const _Refused();
    final List<int> bytes;
    try {
      bytes = base64.decode(base64.normalize(raw));
    } on FormatException {
      return null;
    }
    if (bytes.length > maxDecoded) return const _Refused();
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return null;
    }
    for (final rune in text.runes) {
      if (rune <= 0x1f || (rune >= 0x7f && rune <= 0x9f)) {
        return const _Refused();
      }
    }
    final shown = text.replaceAll(_invisibleFormatting, '');
    return shown.isEmpty ? null : _Text(shown);
  }

  /// Text direction overrides and isolates, zero-width characters and other
  /// invisible formatting, which could make the text read differently from
  /// what it says.
  static final _invisibleFormatting = RegExp(
    '[\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u2064'
    '\u2066-\u206F\uFEFF\uFFF9-\uFFFB]',
  );

  /// The query's answer: the query itself.
  static const queryReply = '\x1b]7501;?\x1b\\';

  @override
  String toString() =>
      'ProgramStatusReport(${state?.name ?? 'clear'}, id: ${id.join('/')}, '
      'kind: ${kind?.name}, progress: $progress, app: $app)';
}

sealed class _Decoded {
  const _Decoded();
}

final class _Text extends _Decoded {
  const _Text(this.text);

  final String text;
}

final class _Refused extends _Decoded {
  const _Refused();
}

/// The state of a ConEmu / Windows Terminal progress bar, `OSC 9 ; 4`.
enum TerminalProgressState { normal, error, indeterminate, paused }

/// `OSC 9 ; 4 ; st ; pr ST`: a single progress bar, used by systemd, winget
/// and others. [TerminalProgress.parse] returns [TerminalProgress.removed] for
/// `st = 0`.
final class TerminalProgress extends TerminalStatusEvent {
  const TerminalProgress(this.state, [this.percent]);

  const TerminalProgress.removed() : state = null, percent = null;

  static const oscCode = '9';

  /// Null when the bar is removed.
  final TerminalProgressState? state;

  /// 0–100; null with [TerminalProgressState.indeterminate] or when not given.
  final int? percent;

  /// Parses the arguments after `9`, or returns null for anything but a
  /// valid `4` subcommand (OSC 9 alone is a desktop notification).
  static TerminalProgress? parse(List<String> args) {
    if (args.isEmpty || args[0] != '4') return null;
    final st = args.length > 1 && args[1].isNotEmpty
        ? int.tryParse(args[1])
        : 0;
    final pr = args.length > 2 ? int.tryParse(args[2]) : null;
    final percent = pr?.clamp(0, 100);
    return switch (st) {
      0 => const TerminalProgress.removed(),
      1 => TerminalProgress(TerminalProgressState.normal, percent ?? 0),
      2 => TerminalProgress(TerminalProgressState.error, percent),
      3 => const TerminalProgress(TerminalProgressState.indeterminate),
      4 => TerminalProgress(TerminalProgressState.paused, percent),
      _ => null,
    };
  }

  @override
  String toString() => 'TerminalProgress(${state?.name}, $percent)';
}

/// Shell integration marks, `OSC 133 ; X`.
enum ShellMarkKind {
  /// `A`: a prompt begins.
  promptStart,

  /// `B`: the prompt ends and the command line begins.
  commandStart,

  /// `C`: the command is executed.
  commandExecuted,

  /// `D`: the command finished, with its exit code when given.
  commandFinished,
}

/// `OSC 133 ; A|B|C|D [; …] ST`, emitted by the shell.
final class ShellMark extends TerminalStatusEvent {
  const ShellMark(this.kind, {this.exitCode});

  static const oscCode = '133';

  final ShellMarkKind kind;

  /// Only with [ShellMarkKind.commandFinished].
  final int? exitCode;

  static ShellMark? parse(List<String> args) {
    if (args.isEmpty) return null;
    final kind = switch (args[0]) {
      'A' => ShellMarkKind.promptStart,
      'B' => ShellMarkKind.commandStart,
      'C' => ShellMarkKind.commandExecuted,
      'D' => ShellMarkKind.commandFinished,
      _ => null,
    };
    if (kind == null) return null;
    return ShellMark(
      kind,
      exitCode: kind == ShellMarkKind.commandFinished && args.length > 1
          ? int.tryParse(args[1])
          : null,
    );
  }

  @override
  String toString() => 'ShellMark(${kind.name}, $exitCode)';
}

/// A full reset (`RIS`): every record goes. A soft reset does not emit this.
final class TerminalStatusReset extends TerminalStatusEvent {
  const TerminalStatusReset();
}

/// One stored record of [ProgramStatusRecords].
final class ProgramStatusRecord {
  const ProgramStatusRecord(this.report);

  final ProgramStatusReport report;

  List<String> get id => report.id;

  ProgramState get state => report.state!;

  String get key => report.id.join('/');
}

/// The last command the shell ran, as told by OSC 133.
final class ShellCommandStatus {
  const ShellCommandStatus.running() : running = true, exitCode = null;

  const ShellCommandStatus.finished(this.exitCode) : running = false;

  final bool running;

  /// Null while running, or when the shell did not report one.
  final int? exitCode;

  bool get failed => exitCode != null && exitCode != 0;
}

/// The status a terminal shows, built from [TerminalStatusEvent]s by the
/// spec's lifetime rules. Who owns it decides what a terminal is: a
/// [Terminal], or each pane of a multiplexer.
class ProgramStatusRecords with Observable {
  ProgramStatusRecords({this.maxRecords = 256}) : assert(maxRecords > 0);

  /// The least recently reported record goes beyond this many.
  final int maxRecords;

  /// Ordered from the least to the most recently reported.
  final _records = <String, ProgramStatusRecord>{};

  TerminalProgress? _progress;

  ShellCommandStatus? _command;

  /// From the least to the most recently reported.
  Iterable<ProgramStatusRecord> get records => _records.values;

  /// The OSC 9;4 progress bar, if one is shown.
  TerminalProgress? get progress => _progress;

  /// The shell's last command, from OSC 133.
  ShellCommandStatus? get command => _command;

  bool get isEmpty => _records.isEmpty && _progress == null && _command == null;

  ProgramStatusRecord? operator [](List<String> id) => _records[id.join('/')];

  /// [record]'s program: its own, or that of its nearest ancestor naming one.
  String? appOf(ProgramStatusRecord record) {
    for (var depth = record.id.length; depth >= 0; depth--) {
      final app = _records[record.id.take(depth).join('/')]?.report.app;
      if (app != null) return app;
    }
    return null;
  }

  /// The most urgent state of all records and the progress bar, or null when
  /// nothing reports one. A running or failed shell command (OSC 133) is not
  /// folded in: see [command].
  ProgramState? get state {
    ProgramState? best;
    for (final record in _records.values) {
      if (best == null || record.state.index < best.index) best = record.state;
    }
    final fromProgress = switch (_progress?.state) {
      null => null,
      TerminalProgressState.error => ProgramState.error,
      _ => ProgramState.working,
    };
    if (fromProgress != null && (best == null || fromProgress.index < best.index)) {
      best = fromProgress;
    }
    return best;
  }

  void apply(TerminalStatusEvent event) {
    final changed = switch (event) {
      ProgramStatusReport() => _report(event),
      TerminalProgress() => _setProgress(event),
      ShellMark() => _mark(event),
      TerminalStatusReset() => _clearAll(),
    };
    if (changed) notifyListeners();
  }

  /// The process attached to the terminal exited.
  void processExited() {
    final dropped = _dropTransient();
    final hadCommand = _command?.running ?? false;
    if (hadCommand) _command = null;
    if (dropped || hadCommand) notifyListeners();
  }

  /// Removes everything, as a full reset does.
  void clear() {
    if (_clearAll()) notifyListeners();
  }

  bool _report(ProgramStatusReport report) {
    final key = report.id.join('/');
    if (report.isClear) {
      if (key.isEmpty) {
        if (_records.isEmpty) return false;
        _records.clear();
        return true;
      }
      final prefix = '$key/';
      final before = _records.length;
      _records.removeWhere((k, _) => k == key || k.startsWith(prefix));
      return _records.length != before;
    }
    // Each report replaces its record whole, and makes it the most recent:
    // nothing changes when it already is, saying the same thing.
    if (_records.isNotEmpty &&
        _records.keys.last == key &&
        _records[key]!.report.sameAs(report)) {
      return false;
    }
    _records.remove(key);
    _records[key] = ProgramStatusRecord(report);
    while (_records.length > maxRecords) {
      _records.remove(_records.keys.first);
    }
    return true;
  }

  bool _setProgress(TerminalProgress progress) {
    final next = progress.state == null ? null : progress;
    if (next?.state == _progress?.state && next?.percent == _progress?.percent) {
      return false;
    }
    _progress = next;
    return true;
  }

  bool _mark(ShellMark mark) {
    switch (mark.kind) {
      case ShellMarkKind.promptStart:
        // A new prompt means the programs before it have exited.
        return _dropTransient();
      case ShellMarkKind.commandStart:
        return false;
      case ShellMarkKind.commandExecuted:
        if (_command?.running ?? false) return false;
        _command = const ShellCommandStatus.running();
        return true;
      case ShellMarkKind.commandFinished:
        final command = _command;
        if (command != null &&
            !command.running &&
            command.exitCode == mark.exitCode) {
          return false;
        }
        _command = ShellCommandStatus.finished(mark.exitCode);
        return true;
    }
  }

  /// Drops `working`, `blocked` and `idle` records and a progress bar that
  /// did not fail: what only means something while its program runs.
  bool _dropTransient() {
    final before = _records.length;
    _records.removeWhere((_, record) => !record.state.persists);
    var changed = _records.length != before;
    if (_progress != null &&
        _progress!.state != TerminalProgressState.error) {
      _progress = null;
      changed = true;
    }
    return changed;
  }

  bool _clearAll() {
    if (isEmpty) return false;
    _records.clear();
    _progress = null;
    _command = null;
    return true;
  }
}
