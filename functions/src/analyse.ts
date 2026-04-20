import { onRequest } from 'firebase-functions/v2/https';
import { checkAndIncrementUsage } from './usageGuard';
import { callGemini } from './gemini';

const REGION = 'us-central1';

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

    // Enforce daily scan limit — rejects with 429 when cap is reached.
    try {
      await checkAndIncrementUsage(userId);
    } catch (err: unknown) {
      if (err instanceof Error && err.message === 'LIMIT_EXCEEDED') {
        res.status(429).json({
          error: 'Daily scan limit reached. Upgrade to Pro for unlimited scans.',
        });
        return;
      }
      throw err;
    }

    const projectId = process.env.GCLOUD_PROJECT;
    if (!projectId) throw new Error('GCLOUD_PROJECT env var is not set');

    // Call Vertex AI and forward the parsed result to the iOS client.
    const rawJson = await callGemini(projectId, gcsUri);

    let parsed: unknown;
    try {
      parsed = JSON.parse(rawJson);
    } catch {
      throw new Error(`Vertex AI returned invalid JSON: ${rawJson}`);
    }

    res.status(200).json(parsed);
  }
);
