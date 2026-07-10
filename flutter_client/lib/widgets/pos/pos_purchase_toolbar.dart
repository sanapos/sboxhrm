import 'package:flutter/material.dart';



import '../../utils/pos_doc_status.dart';
import 'pos_theme.dart';



/// Sidebar lọc kiểu KiotViet cho màn nhập/trả hàng NCC.

class PosPurchaseFilterPanel extends StatelessWidget {

  const PosPurchaseFilterPanel({

    super.key,

    required this.child,

    this.width = 240,

  });



  final Widget child;

  final double width;



  @override

  Widget build(BuildContext context) {

    return Container(

      width: width,

      decoration: BoxDecoration(

        color: Colors.white,

        border: Border(right: BorderSide(color: Colors.grey.shade200)),

      ),

      child: SingleChildScrollView(

        padding: const EdgeInsets.all(12),

        child: child,

      ),

    );

  }

}



Widget purchaseFilterSection(String title, Widget content) => Column(

      crossAxisAlignment: CrossAxisAlignment.stretch,

      children: [

        Text(title,

            style: const TextStyle(

                fontSize: 12, fontWeight: FontWeight.w600, color: PosTheme.textSecondary)),

        const SizedBox(height: 8),

        content,

        const SizedBox(height: 16),

      ],

    );



Widget purchaseStatusChip(String status, {String completedLabel = 'Đã nhập hàng'}) =>
    posDocStatusChip(status, completedLabel: completedLabel);


