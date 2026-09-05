import 'dart:collection';
import 'package:flutter/foundation.dart';

class QueuedSmsEvent {
  final String sender;
  final String body;
  final DateTime timestamp;

  QueuedSmsEvent({
    required this.sender,
    required this.body,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'sender': sender,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
      };
}

class OfflineQueueService extends ChangeNotifier {
  static final OfflineQueueService _instance = OfflineQueueService._internal();
  factory OfflineQueueService() => _instance;
  OfflineQueueService._internal();

  final Queue<QueuedSmsEvent> _queuedEvents = Queue<QueuedSmsEvent>();

  void enqueueSmsEvent(String sender, String body, DateTime timestamp) {
    _queuedEvents.add(QueuedSmsEvent(
      sender: sender,
      body: body,
      timestamp: timestamp,
    ));
    notifyListeners();
  }

  int get pendingQueueCount => _queuedEvents.length;
  List<QueuedSmsEvent> get queuedEvents => List.unmodifiable(_queuedEvents.toList());

  List<QueuedSmsEvent> flushQueue() {
    final List<QueuedSmsEvent> flushed = List.from(_queuedEvents);
    _queuedEvents.clear();
    notifyListeners();
    return flushed;
  }
}
