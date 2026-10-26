import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/cache.dart';

/// Et bilde fra nettet via bufferet på disken ([ImageStore]).
@immutable
class StoredImage extends ImageProvider<StoredImage> {
  const StoredImage(this.url, this.store);

  final String url;
  final ImageStore store;

  @override
  Future<StoredImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture<StoredImage>(this);

  @override
  ImageStreamCompleter loadImage(StoredImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: url);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await store.bytes(url);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is StoredImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Bildet for [url], pakket ut [cacheWidth] piksler bredt (aldri større enn det er): mindre minne, og mindre hakking
/// når du blar. Uten buffer på disken (testene) som et vanlig nettbilde.
ImageProvider<Object> netImageProvider(String url, {int? cacheWidth}) {
  final store = ImageStore.instance;
  final ImageProvider<Object> base = store == null ? NetworkImage(url) : StoredImage(url, store);
  return ResizeImage.resizeIfNeeded(cacheWidth, null, base);
}

/// Bilde fra nettet (logo, plakat, bakgrunn) som tones inn når det kommer, men vises med en gang når det alt er
/// klart, og [fallback] når det ikke kan hentes.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.decodeWidth,
  });

  final String url;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;

  /// bredden bildet vises i (logiske piksler); det pakkes ut i den bredden ganger skjermens tetthet
  final double? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final w = decodeWidth;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return Image(
      image: netImageProvider(url, cacheWidth: w == null || w <= 0 ? null : (w * dpr).round()),
      fit: fit,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => fallback,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
