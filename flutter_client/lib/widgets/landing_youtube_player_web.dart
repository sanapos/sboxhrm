import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

class LandingYoutubePlayerImpl extends StatefulWidget {
  const LandingYoutubePlayerImpl({
    super.key,
    required this.videoId,
    this.autoplay = false,
  });

  final String videoId;
  final bool autoplay;

  @override
  State<LandingYoutubePlayerImpl> createState() =>
      _LandingYoutubePlayerImplState();
}

class _LandingYoutubePlayerImplState extends State<LandingYoutubePlayerImpl> {
  static int _nextId = 0;
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'landing-youtube-player-${_nextId++}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final frame = web.HTMLIFrameElement()
        ..src =
            'https://www.youtube.com/embed/${widget.videoId}?autoplay=${widget.autoplay ? '1' : '0'}&rel=0&modestbranding=1&playsinline=1'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.border = '0'
        ..allow =
            'accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share; fullscreen'
        ..allowFullscreen = true;
      return frame;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
