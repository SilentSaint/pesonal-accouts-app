import 'package:flutter/services.dart';

class SmsReceiverService {
  static const MethodChannel _channel = MethodChannel('com.automaticexpense.tracker/sms');

  static Future<void> initializeSmsListener(Function(String sender, String body) onSmsReceived) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsReceived') {
        final Map<dynamic, dynamic> args = call.arguments;
        final String sender = args['sender'] ?? '';
        final String body = args['body'] ?? '';
        onSmsReceived(sender, body);
      }
    });
  }
}
