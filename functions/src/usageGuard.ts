import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const DAILY_LIMIT = 5;
export const LIMIT_EXCEEDED = 'LIMIT_EXCEEDED';

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
