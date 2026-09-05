import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as google_sign_in_web;

Widget googleSignInButton({
  required Future<void> Function() onUnsupportedPlatformTap,
}) =>
    google_sign_in_web.renderButton();
