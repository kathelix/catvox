const test = require('node:test');
const assert = require('node:assert/strict');

const { getAnalysisPayload, parseAnalysisPayload } = require('../lib/analyse.js');

test('parseAnalysisPayload rejects truncated Vertex JSON', () => {
  const truncatedPayload = `{
    "primary_emotion": "Attentive",
    "confidence_score": 0.9,
    "analysis": "The cat is focused.",
    "persona_type": "The Affectionate Sweetheart",
    "cat_thought": "Ah, you noticed me.",
  `;

  assert.throws(
    () => parseAnalysisPayload(truncatedPayload),
    /Vertex AI returned invalid JSON\./
  );
});

test('parseAnalysisPayload rejects JSON missing required fields', () => {
  const missingFieldPayload = JSON.stringify({
    primary_emotion: 'Attentive',
    confidence_score: 0.9,
    analysis: 'The cat is focused.',
    persona_type: 'The Affectionate Sweetheart',
    cat_thought: 'Ah, you noticed me.',
  });

  assert.throws(
    () => parseAnalysisPayload(missingFieldPayload),
    /Vertex AI returned an invalid analysis payload\./
  );
});

test('getAnalysisPayload retries once after malformed model output', async () => {
  const validPayload = JSON.stringify({
    primary_emotion: 'Attentive',
    confidence_score: 0.9,
    analysis: 'The cat is focused.',
    persona_type: 'The Affectionate Sweetheart',
    cat_thought: 'Ah, you noticed me.',
    owner_tip: 'Offer a gentle interaction.',
  });

  const responses = ['{"primary_emotion":"Attentive"', validPayload];
  let attempts = 0;

  const payload = await getAnalysisPayload(async () => {
    const response = responses[attempts];
    attempts += 1;
    return response;
  });

  assert.equal(attempts, 2);
  assert.deepEqual(payload, JSON.parse(validPayload));
});

test('getAnalysisPayload fails cleanly after repeated malformed output', async () => {
  await assert.rejects(
    () => getAnalysisPayload(async () => '{"primary_emotion":"Attentive"'),
    /Vertex AI returned invalid JSON\./
  );
});
