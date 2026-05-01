import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const DAILY_LIMIT = 5;
export const LIMIT_EXCEEDED = 'LIMIT_EXCEEDED';
export const DAILY_SCAN_QUOTA_EXCEEDED_CODE = 'daily_scan_quota_exceeded';
const DAILY_SCAN_QUOTA_EXCEEDED_MESSAGE =
  'Daily scan limit reached. Come back tomorrow.';

export type QuotaEndpoint = 'getSignedUploadURL' | 'analyseVideo';

export type DailyQuotaExceededBody = {
  code: typeof DAILY_SCAN_QUOTA_EXCEEDED_CODE;
  message: string;
  limit: number;
  remaining: number;
  resetAt: string;
};

type DailyQuotaExceededResponse = {
  body: DailyQuotaExceededBody;
  retryAfterSeconds: number;
};

type QuotaResponseLike = {
  setHeader(name: string, value: string): unknown;
  status(code: number): {
    json(body: DailyQuotaExceededBody): unknown;
  };
};

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Non-mutating quota check used at request gates where we want to reject
 * already-exhausted users without consuming a usage unit yet.
 */
export async function checkUsageAvailable(userId: string): Promise<void> {
  const db = getFirestore();
  const ref = db.collection('usage').doc(userId);
  const today = todayUTC();

  const snap = await ref.get();
  if (!snap.exists) {
    return;
  }

  const data = snap.data()!;
  const isNewDay = data.lastResetDate !== today;
  const count: number = isNewDay ? 0 : data.count;

  if (count >= DAILY_LIMIT) {
    throw new Error(LIMIT_EXCEEDED);
  }
}

/**
 * Records one successful analysis completion for the given user.
 * Resets the counter when the calendar date (UTC) has changed.
 */
export async function incrementUsage(userId: string): Promise<void> {
  const db = getFirestore();
  const ref = db.collection('usage').doc(userId);
  const today = todayUTC();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);

    if (!snap.exists) {
      tx.set(ref, { count: 1, lastResetDate: today });
      return;
    }

    const data = snap.data()!;
    const isNewDay = data.lastResetDate !== today;

    if (isNewDay) {
      tx.set(ref, { count: 1, lastResetDate: today });
    } else {
      tx.update(ref, { count: FieldValue.increment(1) });
    }
  });
}

export function isLimitExceededError(err: unknown): boolean {
  return err instanceof Error && err.message === LIMIT_EXCEEDED;
}

export function buildDailyQuotaExceededResponse(
  now = new Date()
): DailyQuotaExceededResponse {
  const resetAt = nextUTCDate(now);
  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((resetAt.getTime() - now.getTime()) / 1000)
  );

  return {
    body: {
      code: DAILY_SCAN_QUOTA_EXCEEDED_CODE,
      message: DAILY_SCAN_QUOTA_EXCEEDED_MESSAGE,
      limit: DAILY_LIMIT,
      remaining: 0,
      resetAt: formatUTCInstant(resetAt),
    },
    retryAfterSeconds,
  };
}

export function sendDailyQuotaExceededResponse(
  res: QuotaResponseLike,
  endpoint: QuotaEndpoint
): void {
  const { body, retryAfterSeconds } = buildDailyQuotaExceededResponse();

  logger.info('quota_exceeded', {
    event: 'quota_exceeded',
    quotaType: 'daily_scan',
    endpoint,
    limit: body.limit,
    remaining: body.remaining,
    resetAt: body.resetAt,
  });

  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Retry-After', String(retryAfterSeconds));
  res.status(429).json(body);
}

function nextUTCDate(from: Date): Date {
  return new Date(Date.UTC(
    from.getUTCFullYear(),
    from.getUTCMonth(),
    from.getUTCDate() + 1,
    0,
    0,
    0,
    0
  ));
}

function formatUTCInstant(date: Date): string {
  return date.toISOString().replace('.000Z', 'Z');
}
