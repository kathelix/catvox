import { onRequest } from 'firebase-functions/v2/https';
import { getStorage } from 'firebase-admin/storage';
import { randomUUID } from 'crypto';
import { checkUsageAvailable, isLimitExceededError } from './usageGuard';

const REGION = 'us-central1';
const URL_TTL_MS = 15 * 60 * 1000; // 15 minutes — enough for any upload

export const getSignedUploadURL = onRequest(
  {
    region: REGION,
    invoker: 'public', // Unauthenticated iOS clients must reach this endpoint.
    // Security boundary: Firebase App Check (ADR-0002) — enforce once wired in iOS.
    serviceAccount: 'catvox-backend-sa@kathelix-catvox-prod.iam.gserviceaccount.com',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const { filename, contentType, userId } = req.body as {
      filename?: string;
      contentType?: string;
      userId?: string;
    };

    if (!filename || !contentType || !userId) {
      res.status(400).json({ error: 'filename, contentType, and userId are required' });
      return;
    }

    try {
      await checkUsageAvailable(userId);
    } catch (err: unknown) {
      if (isLimitExceededError(err)) {
        res.status(429).json({
          error: 'Daily scan limit reached. Upgrade to Pro for unlimited scans.',
        });
        return;
      }
      throw err;
    }

    const projectId = process.env.GCLOUD_PROJECT;
    if (!projectId) throw new Error('GCLOUD_PROJECT env var is not set');

    const bucketName = `catvox-raw-videos-${projectId}`;
    const objectName = `${randomUUID()}-${filename}`;

    const bucket = getStorage().bucket(bucketName);
    const file = bucket.file(objectName);

    const [signedUrl] = await file.getSignedUrl({
      version: 'v4',
      action: 'write',
      expires: Date.now() + URL_TTL_MS,
      contentType,
    });

    const gcsUri = `gs://${bucketName}/${objectName}`;

    res.status(200).json({ signedUrl, gcsUri });
  }
);
