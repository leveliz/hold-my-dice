import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Pixels of a square tile of faint speckle: each pixel is either a whisper of
/// white or a whisper of black. Laid over a dark gradient it breaks the steps
/// between neighbouring shades into fine grain, so the gradient looks smooth
/// instead of banded (a dark screen has few shades to spread a gradient over).
///
/// Colours are premultiplied (white is as bright as it is opaque), so the tile
/// reads the same whichever way the engine treats the bytes.
Uint8List buildNoiseTile({int size = 64, int seed = 7, int maxAlpha = 5}) {
  final random = Random(seed);
  final pixels = Uint8List(size * size * 4);
  for (var i = 0; i < size * size; i++) {
    final alpha = 1 + random.nextInt(maxAlpha);
    final white = random.nextBool();
    final level = white ? alpha : 0;
    pixels[i * 4] = level;
    pixels[i * 4 + 1] = level;
    pixels[i * 4 + 2] = level;
    pixels[i * 4 + 3] = alpha;
  }
  return pixels;
}

const _tileSize = 64;

/// Decodes the speckle tile once for the whole app.
class NoiseTile {
  static ui.Image? _image;
  static Future<void>? _loading;

  /// Bumped when the tile is ready, so overlays repaint.
  static final loaded = ValueNotifier<int>(0);

  static ui.Image? get image => _image;

  static void ensureLoaded() => _loading ??= _load();

  /// Completes once the tile is decoded.
  static Future<void> get ready {
    ensureLoaded();
    return _loading!;
  }

  /// Forgets the decoded tile, so a test starts from the unloaded state.
  @visibleForTesting
  static void resetForTest() {
    _image = null;
    _loading = null;
    loaded.value = 0;
  }

  static Future<void> _load() async {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      buildNoiseTile(size: _tileSize),
      _tileSize,
      _tileSize,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    _image = await done.future;
    loaded.value++;
  }
}

/// Fills its box with the speckle, one speckle per screen pixel. Ignores
/// touches. Draws nothing until the tile has been decoded.
class DitherOverlay extends StatelessWidget {
  const DitherOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    NoiseTile.ensureLoaded();
    final scale = MediaQuery.devicePixelRatioOf(context);
    return IgnorePointer(
      child: ValueListenableBuilder<int>(
        valueListenable: NoiseTile.loaded,
        builder: (context, _, _) => CustomPaint(
          painter: _DitherPainter(NoiseTile.image, scale),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DitherPainter extends CustomPainter {
  _DitherPainter(this.image, this.scale);

  final ui.Image? image;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final tile = image;
    if (tile == null) return;
    final paint = Paint()
      ..shader = ui.ImageShader(
        tile,
        TileMode.repeated,
        TileMode.repeated,
        Float64List.fromList([
          1 / scale, 0, 0, 0, //
          0, 1 / scale, 0, 0, //
          0, 0, 1, 0, //
          0, 0, 0, 1,
        ]),
        filterQuality: FilterQuality.none,
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_DitherPainter old) =>
      old.image != image || old.scale != scale;
}
