const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildDailyQuotaExceededResponse,
  sendDailyQuotaExceededResponse,
} = require('../lib/usageGuard.js');

test('buildDailyQuotaExceededResponse returns machine-readable daily quota payload', () => {
  const now = new Date('2026-05-01T09:15:16.973Z');

  const response = buildDailyQuotaExceededResponse(now);

  assert.deepEqual(response.body, {
    code: 'daily_scan_quota_exceeded',
    message: 'Daily scan limit reached. Come back tomorrow.',
    limit: 5,
    remaining: 0,
    resetAt: '2026-05-02T00:00:00Z',
  });
});

test('buildDailyQuotaExceededResponse retryAfter matches next UTC reset', () => {
  const now = new Date('2026-05-01T23:59:59.250Z');

  const response = buildDailyQuotaExceededResponse(now);

  assert.equal(response.body.resetAt, '2026-05-02T00:00:00Z');
  assert.equal(response.retryAfterSeconds, 1);
});

test('sendDailyQuotaExceededResponse writes status, headers, and shared body', () => {
  const calls = {
    headers: {},
    statusCode: null,
    body: null,
  };
  const res = {
    setHeader(name, value) {
      calls.headers[name] = value;
      return this;
    },
    status(code) {
      calls.statusCode = code;
      return {
        json(body) {
          calls.body = body;
        },
      };
    },
  };

  sendDailyQuotaExceededResponse(res, 'getSignedUploadURL');

  assert.equal(calls.statusCode, 429);
  assert.equal(calls.headers['Content-Type'], 'application/json');
  assert.match(calls.headers['Retry-After'], /^[1-9]\d*$/);
  assert.equal(calls.body.code, 'daily_scan_quota_exceeded');
  assert.equal(calls.body.limit, 5);
  assert.equal(calls.body.remaining, 0);
});
