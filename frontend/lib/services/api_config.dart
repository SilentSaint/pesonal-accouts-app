class ApiConfig {
  static const String defaultLocalUrl = 'http://localhost:8080/api';

  static String baseUrl = defaultLocalUrl;

  static void useCustomApiEndpoint(String apiEndpoint) {
    if (apiEndpoint.isEmpty) return;
    baseUrl = apiEndpoint.endsWith('/api') ? apiEndpoint : '$apiEndpoint/api';
  }

  static void resetToDefault() {
    baseUrl = defaultLocalUrl;
  }
}
