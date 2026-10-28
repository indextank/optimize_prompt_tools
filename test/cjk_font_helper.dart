/// Resolve the Noto CJK font used to generate committed goldens.
///
/// Golden images in this repo were produced with Noto Sans CJK on Linux.
/// Windows system fonts (msyh/simhei) will not match those goldens, so visual
/// suites must skip unless the same Noto path is present.
library;

import 'dart:io';

/// Paths that match goldens committed from Linux CI / local runs.
const List<String> kGoldenCjkFontCandidates = [
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
];

/// Returns a font path only when it can match existing goldens; else null.
String? findHostCjkFontPath() {
  for (final path in kGoldenCjkFontCandidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// Skip reason when no matching CJK font is available.
const String kNoCjkFontSkip = 'Golden CJK font (Noto) not available on host';
