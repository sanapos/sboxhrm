import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
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
      color: SboxColors.slate900,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline_rounded,
              color: Colors.white70, size: 56),
          SizedBox(height: 12),
          Text(tr('Trình phát trực tiếp hiện hỗ trợ trên bản web.'),
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
