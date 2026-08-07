import "package:flutter/material.dart";
class PageTopActions extends StatelessWidget { const PageTopActions({super.key, this.children = const []}); final List<Widget> children; @override Widget build(BuildContext context) => Row(children: children); }
