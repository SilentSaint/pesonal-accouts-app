import 'package:flutter/material.dart';

Widget googleSignInButton({
  required Future<void> Function() onUnsupportedPlatformTap,
}) {
  return FilledButton.icon(
    onPressed: onUnsupportedPlatformTap,
    icon: const Icon(Icons.login),
    label: const Text('Sign in to unlock'),
  );
}
