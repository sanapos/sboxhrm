import 'package:flutter/material.dart';

class LandingYoutubePlayerImpl extends StatelessWidget {
  const LandingYoutubePlayerImpl({
    super.key,
    required this.videoId,
    this.autoplay = false,
  });

  final String videoId;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline_rounded,
              color: Colors.white70, size: 56),
          SizedBox(height: 12),
          Text(
            'Trình phát trực tiếp hiện hỗ trợ trên bản web.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
