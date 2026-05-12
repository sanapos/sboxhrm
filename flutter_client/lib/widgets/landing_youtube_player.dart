import 'package:flutter/material.dart';

import 'landing_youtube_player_stub.dart'
    if (dart.library.html) 'landing_youtube_player_web.dart' as impl;

class LandingYoutubePlayer extends StatelessWidget {
  const LandingYoutubePlayer({
    super.key,
    required this.videoId,
    this.autoplay = false,
  });

  final String videoId;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    return impl.LandingYoutubePlayerImpl(
      videoId: videoId,
      autoplay: autoplay,
    );
  }
}
