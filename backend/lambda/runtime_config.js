function parseGeminiApiKey(secretValue) {
  const value = secretValue?.trim();
  if (!value) return null;

  if (!value.startsWith('{')) return value;

  try {
    const parsed = JSON.parse(value);
    return typeof parsed.GEMINI_API_KEY === 'string' &&
            parsed.GEMINI_API_KEY.trim().length > 0
        ? parsed.GEMINI_API_KEY.trim()
        : null;
  } catch (_) {
    return null;
  }
}

module.exports = { parseGeminiApiKey };
