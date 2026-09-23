import 'package:flutter/material.dart';

class HomeNavigation {
  HomeNavigation._();

  static VoidCallback? _goHomeHandler;

  static void register(VoidCallback handler) {
    _goHomeHandler = handler;
  }

  static void unregister() {
    _goHomeHandler = null;
  }

  static void goHome(BuildContext context) {
    _goHomeHandler?.call();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
