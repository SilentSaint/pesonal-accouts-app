import 'package:flutter/services.dart';

import '../domain/sms_ingestion_port.dart';

class AndroidSmsIngestionAdapter implements SmsIngestionPort {
  AndroidSmsIngestionAdapter({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.automaticexpense.tracker/sms');

  final MethodChannel _channel;

  @override
  Future<void> initialize(void Function() onEventAvailable) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSmsCaptured') onEventAvailable();
    });
  }

  @override
  Future<SmsCaptureStatus> captureStatus() => _status('getSmsCaptureStatus');

  @override
  Future<SmsCaptureStatus> requestCaptureAuthorization() =>
      _status('requestSmsCaptureAuthorization');

  Future<SmsCaptureStatus> _status(String method) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(method);
      return SmsCaptureStatus.fromMap(raw ?? const {});
    } on PlatformException {
      return const SmsCaptureStatus(
        isSupported: false,
        isEnabled: false,
        hasReceivePermission: false,
      );
    } on MissingPluginException {
      return const SmsCaptureStatus(
        isSupported: false,
        isEnabled: false,
        hasReceivePermission: false,
      );
    }
  }

  @override
  Future<List<SmsCaptureEvent>> pendingEvents() async {
    try {
      final events = await _channel.invokeListMethod<Object?>(
            'getPendingSmsCaptureEvents',
          ) ??
          const [];
      return events
          .whereType<Map<Object?, Object?>>()
          .map(SmsCaptureEvent.fromMap)
          .toList();
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> acknowledge(String eventId) =>
      _channel.invokeMethod<void>('acknowledgeSmsCaptureEvent', {
        'id': eventId,
      });
}
