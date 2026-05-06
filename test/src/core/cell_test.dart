import 'package:test/test.dart';
import 'package:xterm/src/core/cell.dart';

void main() {
  group('CellData', () {
    test('empty factory creates zero-initialized cell', () {
      final cell = CellData.empty();
      expect(cell.foreground, 0);
      expect(cell.background, 0);
      expect(cell.flags, 0);
      expect(cell.content, 0);
    });

    test('getHash produces deterministic results', () {
      final cell1 = CellData(foreground: 1, background: 2, flags: 3, content: 4);
      final cell2 = CellData(foreground: 1, background: 2, flags: 3, content: 4);
      expect(cell1.getHash(), cell2.getHash());
    });

    test('different content produces different hash', () {
      final cell1 = CellData(foreground: 1, background: 2, flags: 3, content: 4);
      final cell2 = CellData(foreground: 1, background: 2, flags: 3, content: 5);
      expect(cell1.getHash(), isNot(cell2.getHash()));
    });

    test('mutable fields can be updated after construction', () {
      final cell = CellData(foreground: 1, background: 2, flags: 3, content: 4);
      cell.foreground = 10;
      cell.background = 20;
      cell.flags = 30;
      cell.content = 40;
      expect(cell.foreground, 10);
      expect(cell.background, 20);
      expect(cell.flags, 30);
      expect(cell.content, 40);
    });
  });

  group('CellAttr', () {
    test('constants have distinct bit positions', () {
      // Spot-check no overlap up to overline
      final all = CellAttr.bold |
          CellAttr.faint |
          CellAttr.italic |
          CellAttr.underline |
          CellAttr.blink |
          CellAttr.inverse |
          CellAttr.invisible |
          CellAttr.strikethrough |
          CellAttr.overline;
      expect(all, (1 << 9) - 1);
    });
  });

  group('CellColor', () {
    test('masks and type shift are correct', () {
      expect(CellColor.normal, 0);
      expect(CellColor.named, 1 << CellColor.typeShift);
      expect(CellColor.palette, 2 << CellColor.typeShift);
      expect(CellColor.rgb, 3 << CellColor.typeShift);
    });

    test('type mask extracts color type bits', () {
      expect(CellColor.named & CellColor.typeMask, CellColor.named);
      expect(CellColor.palette & CellColor.typeMask, CellColor.palette);
    });
  });

  group('CellContent', () {
    test('codepoint mask covers 21 bits', () {
      expect(CellContent.codepointMask, 0x1fffff);
    });

    test('width shift aligns with the codepoint mask', () {
      expect(CellContent.widthShift, 22);
    });
  });
}
