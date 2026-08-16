import 'dart:collection';

class OfflineQueueService {
  final Queue<Map<String, dynamic>> _queuedEvents = Queue<Map<String, dynamic>>();

  void enqueueSmsEvent(String sender, String body, DateTime timestamp) {
    _queuedEvents.add({
      'sender': sender,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  int get pendingQueueCount => _queuedEvents.length;

  List<Map<String, dynamic>> flushQueue() {
    final List<Map<String, dynamic>> flushed = List.from(_queuedEvents);
    _queuedEvents.clear();
    return flushed;
  }
}
