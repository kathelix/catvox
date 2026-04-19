import { onRequest } from 'firebase-functions/v2/https';
import { getStorage } from 'firebase-admin/storage';
import { randomUUID } from 'crypto';

const REGION = 'us-central1';
const URL_TTL_MS = 15 * 60 * 1000; // 15 minutes — enough for any upload

export const getSignedUploadURL = onRequest(
  {
    region: REGION,
    // TODO: enforce App Check once wired in the iOS app (ADR-0002).
    // In firebase-functions v5, App Check enforcement on onRequest uses
    // request.app token validation middleware rather than an HttpsOptions flag.
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const { filename, contentType } = req.body as {
      filename?: string;
      contentType?: string;
    };

    if (!filename || !contentType) {
      res.status(400).json({ error: 'filename and contentType are required' });
      return;
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
