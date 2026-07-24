import 'dart:ui' as ui;

/// One text line of a label: the text plus its font size in points.
class LabelLine {
  final String text;
  final double sizePt;
  const LabelLine(this.text, this.sizePt);
}

/// Draws a label onto [canvas] at [pxPerMm] pixels (or printer dots) per mm.
///
/// This is the single source of truth for label layout, shared by the
/// on-screen preview (via CustomPaint) and the Bluetooth print bitmap, so the
/// two are guaranteed to look identical. The reference density is 6.4 px/mm
/// (the preview); font sizes and spacing scale linearly with [pxPerMm], so the
/// print bitmap at 8 dots/mm reproduces the exact same physical layout.
void paintLabel(
  ui.Canvas canvas, {
  required double widthMm,
  required double heightMm,
  required List<LabelLine> lines,
  required double leftPaddingPercent,
  required double verticalGapPt,
  required double pxPerMm,
  bool fillBackground = true,
}) {
  final double widthPx = widthMm * pxPerMm;
  final double heightPx = heightMm * pxPerMm;

  if (fillBackground) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, widthPx, heightPx),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }

  final double density = pxPerMm / 6.4; // relative to the 6.4 px/mm reference
  final double scale = (widthMm / 50.0).clamp(0.5, 2.0);
  final double x = (widthPx * (leftPaddingPercent / 100.0))
      .clamp(4.0 * density, widthPx - 8.0 * density);
  final double rightPad = 13.5 * density;
  final double gap = verticalGapPt * scale * 0.97 * density;
  final double availWidth = (widthPx - x - rightPad).clamp(1.0, widthPx);

  final List<ui.Paragraph> paras = [];
  for (final line in lines) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ui.TextAlign.left,
      fontSize: line.sizePt * 1.734 * scale * density,
      fontWeight: ui.FontWeight.bold,
      maxLines: 1,
      ellipsis: '…',
    ))
      ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
      ..addText(line.text);
    final p = builder.build()
      ..layout(ui.ParagraphConstraints(width: availWidth));
    paras.add(p);
  }

  final double totalH = paras.fold<double>(0.0, (s, p) => s + p.height) +
      (paras.isEmpty ? 0 : gap * (paras.length - 1));
  double y = ((heightPx - totalH) / 2).clamp(0.0, heightPx);
  for (final p in paras) {
    canvas.drawParagraph(p, ui.Offset(x, y));
    y += p.height + gap;
  }
}
