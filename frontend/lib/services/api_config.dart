class ApiConfig {
  static String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://6nyqikrpbb.execute-api.ap-south-2.amazonaws.com/api',
  );
  static const String websocketUrl =
      String.fromEnvironment('WEBSOCKET_SYNC_URL', defaultValue: '');

  static void useCustomApiEndpoint(String apiEndpoint) {
    if (apiEndpoint.isEmpty) return;
    baseUrl = apiEndpoint.endsWith('/api') ? apiEndpoint : '$apiEndpoint/api';
  }

  static void resetToDefault() {
    baseUrl = 'https://6nyqikrpbb.execute-api.ap-south-2.amazonaws.com/api';
  }
}
