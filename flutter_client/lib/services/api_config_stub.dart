String getApiBaseUrl() {
  return const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sboxhrm.com',
  );
}
