import "package:flutter/material.dart";
class HrmPushedScreenShell extends StatelessWidget {
  const HrmPushedScreenShell({super.key, required this.child, this.title});
  final Widget child; final String? title;
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title ?? "")), body: child);
}
