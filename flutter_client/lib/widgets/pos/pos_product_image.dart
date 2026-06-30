import 'package:flutter/material.dart';



import '../../services/api_service.dart';

import '../auth_cached_image.dart';

import 'pos_theme.dart';



/// Ảnh sản phẩm POS — thử path đã lưu, fallback API `/api/pos/products/{id}/image`.

class PosProductImage extends StatelessWidget {

  const PosProductImage({

    super.key,

    this.productId,

    required this.imageUrl,

    this.size = 36,

    this.borderRadius = 4,

  });



  final String? productId;

  final String? imageUrl;

  final double size;

  final double borderRadius;



  static final _api = ApiService();



  @override

  Widget build(BuildContext context) {

    final hasId = productId != null && productId!.isNotEmpty;

    final url = imageUrl?.trim();

    final hasUrl = url != null && url.isNotEmpty;



    if (!hasId && !hasUrl) {

      return _placeholder();

    }



    return ClipRRect(

      borderRadius: BorderRadius.circular(borderRadius),

      child: _PosProductImageLoader(

        paths: [

          if (hasUrl) url!,

          if (hasId) ApiService.posProductImagePath(productId!),

        ],

        apiService: _api,

        size: size,

        placeholder: _placeholder(),

      ),

    );

  }



  Widget _placeholder() {

    return Container(

      width: size,

      height: size,

      decoration: BoxDecoration(

        color: const Color(0xFFF0F2F5),

        borderRadius: BorderRadius.circular(borderRadius),

        border: Border.all(color: PosTheme.border),

      ),

      child: Icon(Icons.image_outlined, size: size * 0.45, color: Colors.grey.shade500),

    );

  }

}



class _PosProductImageLoader extends StatefulWidget {

  const _PosProductImageLoader({

    required this.paths,

    required this.apiService,

    required this.size,

    required this.placeholder,

  });



  final List<String> paths;

  final ApiService apiService;

  final double size;

  final Widget placeholder;



  @override

  State<_PosProductImageLoader> createState() => _PosProductImageLoaderState();

}



class _PosProductImageLoaderState extends State<_PosProductImageLoader> {

  int _pathIndex = 0;



  @override

  Widget build(BuildContext context) {

    if (_pathIndex >= widget.paths.length) {

      return widget.placeholder;

    }



    return AuthCachedImage(

      key: ValueKey(widget.paths[_pathIndex]),

      imagePath: widget.paths[_pathIndex],

      apiService: widget.apiService,

      width: widget.size,

      height: widget.size,

      fit: BoxFit.cover,

      errorWidget: (_, __, ___) {

        if (_pathIndex + 1 < widget.paths.length) {

          WidgetsBinding.instance.addPostFrameCallback((_) {

            if (mounted) setState(() => _pathIndex++);

          });

        }

        return widget.placeholder;

      },

      placeholder: (_, __) => SizedBox(

        width: widget.size,

        height: widget.size,

        child: const Center(

          child: SizedBox(

            width: 16,

            height: 16,

            child: CircularProgressIndicator(strokeWidth: 2),

          ),

        ),

      ),

    );

  }

}


