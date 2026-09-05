const assert = require('node:assert/strict');
const test = require('node:test');

const { parseGeminiApiKey } = require('../runtime_config');

test('accepts a raw Gemini API key stored in Secrets Manager', () => {
  assert.equal(parseGeminiApiKey('test-api-key'), 'test-api-key');
});

test('accepts a JSON Gemini API key stored in Secrets Manager', () => {
  assert.equal(
    parseGeminiApiKey('{"GEMINI_API_KEY":"test-api-key"}'),
    'test-api-key',
  );
});

test('rejects an empty or unrecognized secret value', () => {
  assert.equal(parseGeminiApiKey(''), null);
  assert.equal(parseGeminiApiKey('{"unexpected":"value"}'), null);
});
