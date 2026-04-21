import { onRequest } from 'firebase-functions/v2/https';
import { getStorage } from 'firebase-admin/storage';
import {
  checkUsageAvailable,
  incrementUsage,
  isLimitExceededError,
} from './usageGuard';
import { callGemini } from './gemini';

const REGION = 'us-central1';
const MAX_UPLOAD_BYTES = 100 * 1024 * 1024;

export const analyseVideo = onRequest(
  {
    region: REGION,
    invoker: 'public', // Unauthenticated iOS clients must reach this endpoint.
    // Security boundary: Firebase App Check (ADR-0002) — enforce once wired in iOS.
    serviceAccount: 'catvox-backend-sa@kathelix-catvox-prod.iam.gserviceaccount.com',
    timeoutSeconds: 120, // Vertex AI multimodal calls can take up to ~30s; headroom for retries.
    memory: '512MiB',
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).send('Method Not Allowed');
      return;
    }

    const { gcsUri, userId } = req.body as {
      gcsUri?: string;
      userId?: string;
    };

    if (!gcsUri || !userId) {
      res.status(400).json({ error: 'gcsUri and userId are required' });
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

    const objectInfo = parseGcsUri(gcsUri);
    if (!objectInfo) {
      res.status(400).json({ error: 'Invalid gcsUri' });
      return;
    }

    const file = getStorage().bucket(objectInfo.bucketName).file(objectInfo.objectName);
    const [metadata] = await file.getMetadata();

    const sizeBytes = Number(metadata.size ?? 0);
    if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) {
      res.status(400).json({ error: 'Uploaded video metadata is missing a valid size.' });
      return;
    }

    if (sizeBytes > MAX_UPLOAD_BYTES) {
      res.status(413).json({
        error: 'Uploaded video exceeds the 100 MB limit.',
      });
      return;
    }

    const mimeType = normalizedVertexVideoMimeType(metadata.contentType);
    if (!mimeType) {
      res.status(400).json({ error: 'Uploaded object is not a supported video.' });
      return;
    }

    // Call Vertex AI and forward the parsed result to the iOS client.
    const rawJson = await callGemini(projectId, gcsUri, mimeType);

    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      throw new Error(`Vertex AI returned invalid JSON: ${rawJson}`);
    }

    await incrementUsage(userId);
    res.status(200).json(parsed);
  }
);

function parseGcsUri(gcsUri: string): { bucketName: string; objectName: string } | null {
  const match = /^gs:\/\/([^/]+)\/(.+)$/.exec(gcsUri);
  if (!match) {
    return null;
  }

  return {
    bucketName: match[1],
    objectName: match[2],
  };
}

function normalizedVertexVideoMimeType(contentType?: string): string | null {
  switch (contentType) {
    case 'video/mp4':
    case 'video/mov':
    case 'video/quicktime':
    case 'video/mpeg':
    case 'video/mpg':
    case 'video/avi':
    case 'video/wmv':
    case 'video/mpegps':
    case 'video/flv':
    case 'video/x-flv':
      return contentType;
    case 'video/x-m4v':
      return 'video/mp4';
    default:
      return null;
  }
}
