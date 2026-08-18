class ApiConfig {
  static const String localDevUrl = 'http://localhost:8080/api';
  static const String awsLambdaUrl = 'https://api.automaticexpense.com/prod/api';

  static String baseUrl = localDevUrl;

  static void useAwsLambdaApi(String apiGatewayEndpoint) {
    baseUrl = apiGatewayEndpoint.endsWith('/api') ? apiGatewayEndpoint : '$apiGatewayEndpoint/api';
  }

  static void useLocalDevApi() {
    baseUrl = localDevUrl;
  }
}
