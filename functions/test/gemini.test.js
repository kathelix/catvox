const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ANALYSIS_GENERATION_CONFIG,
  ANALYSIS_RESPONSE_SCHEMA,
} = require('../lib/gemini.js');

test('analysis generation config uses response schema with required fields', () => {
  assert.equal(ANALYSIS_GENERATION_CONFIG.responseMimeType, 'application/json');
  assert.equal(
    ANALYSIS_GENERATION_CONFIG.responseSchema,
    ANALYSIS_RESPONSE_SCHEMA
  );
  assert.deepEqual(ANALYSIS_RESPONSE_SCHEMA.required, [
    'primary_emotion',
    'confidence_score',
    'analysis',
    'persona_type',
    'cat_thought',
    'owner_tip',
  ]);
});

test('analysis response schema provides meaningful field descriptions', () => {
  const properties = ANALYSIS_RESPONSE_SCHEMA.properties ?? {};

  for (const key of [
    'primary_emotion',
    'confidence_score',
    'analysis',
    'persona_type',
    'cat_thought',
    'owner_tip',
  ]) {
    assert.equal(typeof properties[key]?.description, 'string');
    assert.notEqual(properties[key].description.trim(), '');
  }

  assert.equal(properties.confidence_score?.format, 'double');
  assert.match(properties.confidence_score?.description ?? '', /0\.00 to 1\.00/);
  assert.match(
    properties.persona_type?.description ?? '',
    /current persona names defined by the system instruction/
  );
});
