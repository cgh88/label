import 'dart:ui' as ui;

/// One text line of a label: the text plus its font size in points,
/// and an optional fallback text if the main text exceeds available width.
class LabelLine {
  final String text;
  final double sizePt;
  final String? fallbackText;

  const LabelLine(this.text, this.sizePt, {this.fallbackText});
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
      .clamp(3.0 * density, widthPx - 6.0 * density);
  final double rightPad = 6.0 * density;
  final double gap = verticalGapPt * scale * 0.97 * density;
  final double availWidth = (widthPx - x - rightPad).clamp(1.0, widthPx);

  final List<ui.Paragraph> paras = [];
  for (final line in lines) {
    if (line.text.isEmpty) continue;

    double curFontSize = line.sizePt * 1.734 * scale * density;

    ui.Paragraph buildParagraph(String textStr, double fSize) {
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.left,
        fontSize: fSize,
        fontWeight: ui.FontWeight.bold,
        maxLines: 1,
        fontFamily: 'NotoSansKR',
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFF000000),
          fontFamily: 'NotoSansKR',
        ))
        ..addText(textStr);
      final p = builder.build()
        ..layout(ui.ParagraphConstraints(width: availWidth * 2.0));
      return p;
    }

    ui.Paragraph p = buildParagraph(line.text, curFontSize);

    // If text width exceeds available width, try fallbackText first
    if (line.fallbackText != null && line.fallbackText!.isNotEmpty) {
      if (p.maxIntrinsicWidth > (availWidth + 0.1)) {
        p = buildParagraph(line.fallbackText!, curFontSize);
      }
    }

    // If still exceeding width, shrink font size slightly so full date/text is never cut off
    while (p.maxIntrinsicWidth > (availWidth + 0.1) && curFontSize > 5.0 * density) {
      curFontSize -= 0.4 * density;
      final String renderText = (line.fallbackText != null && line.fallbackText!.isNotEmpty && p.maxIntrinsicWidth > (availWidth + 0.1))
          ? line.fallbackText!
          : line.text;
      p = buildParagraph(renderText, curFontSize);
    }

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
