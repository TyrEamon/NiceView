import 'package:flutter/material.dart';

void showTopSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.only(
          left: 16,
          right: 16,
          top: MediaQuery.paddingOf(context).top + 12,
          bottom: MediaQuery.sizeOf(context).height -
              MediaQuery.paddingOf(context).top -
              112,
        ),
      ),
    );
}
