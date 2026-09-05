import 'dart:async';
import 'dart:html' as html;

void downloadReport(
  List<int> bytes, {
  required String filename,
  required String mimeType,
}) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  Timer.run(() => html.Url.revokeObjectUrl(url));
}
