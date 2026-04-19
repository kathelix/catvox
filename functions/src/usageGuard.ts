import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const DAILY_LIMIT = 5;

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD
}

/**
 * Atomically checks and increments the daily scan count for a user.
 * Resets the counter when the calendar date (UTC) has changed.
 * Throws with message 'LIMIT_EXCEEDED' when the daily cap is reached.
 */
export async function checkAndIncrementUsage(userId: string): Promise<void> {
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
    const count: number = isNewDay ? 0 : data.count;

    if (count >= DAILY_LIMIT) {
      throw new Error('LIMIT_EXCEEDED');
    }

    if (isNewDay) {
      tx.set(ref, { count: 1, lastResetDate: today });
    } else {
      tx.update(ref, { count: FieldValue.increment(1) });
    }
  });
}
