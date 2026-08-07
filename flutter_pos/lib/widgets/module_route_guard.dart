import "package:flutter/material.dart";
class ModuleRouteGuard extends StatelessWidget {
  const ModuleRouteGuard({super.key, required this.child, this.moduleCode});
  final Widget child; final String? moduleCode;
  @override Widget build(BuildContext context) => child;
}
