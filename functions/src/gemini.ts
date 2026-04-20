import {
  VertexAI,
  HarmCategory,
  HarmBlockThreshold,
} from '@google-cloud/vertexai';
import { readFileSync } from 'fs';
import { join } from 'path';

const LOCATION = 'us-central1';
// Gemini 2.5 Flash is a thinking model: thinking tokens are consumed before
// the visible output is written. 300 was calibrated for non-thinking models
// and leaves no budget for the actual JSON response once reasoning runs.
// 1024 output tokens gives the model room to reason and still emit compact JSON.
const MAX_OUTPUT_TOKENS = 1024;

// Gemini 2.5 Flash is the current GA model on Vertex AI.
// Gemini 3.x Flash is in preview only — upgrade when GA.
// Verify at https://cloud.google.com/vertex-ai/generative-ai/docs/learn/models
const MODEL = 'gemini-2.5-flash';

// Safety settings — BLOCK_ONLY_HIGH across all categories.
// Critical for CatVox: standard violence thresholds would trigger on natural
// feline hunting and play-fighting behaviour. (See docs/TODO.md)
const SAFETY_SETTINGS = [
  HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
  HarmCategory.HARM_CATEGORY_HARASSMENT,
  HarmCategory.HARM_CATEGORY_HATE_SPEECH,
  HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
].map((category) => ({
  category,
  threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
}));

// Loaded from docs/Instructions.md at build time (copied to assets/ by the
// build script). Edit docs/Instructions.md to change the prompt — no .ts
// changes needed.
const SYSTEM_INSTRUCTION = readFileSync(
  join(__dirname, '../assets/instructions.md'),
  'utf-8'
);

/**
 * Calls Vertex AI Gemini with the given GCS video URI.
 * Returns the raw JSON string from the model (not yet parsed).
 */
export async function callGemini(
  projectId: string,
  gcsUri: string
): Promise<string> {
  const vertexAI = new VertexAI({ project: projectId, location: LOCATION });

  const model = vertexAI.getGenerativeModel({
    model: MODEL,
    systemInstruction: SYSTEM_INSTRUCTION,
    generationConfig: {
      temperature: 0.7,
      maxOutputTokens: MAX_OUTPUT_TOKENS,
      responseMimeType: 'application/json',
    },
    safetySettings: SAFETY_SETTINGS,
  });

  const result = await model.generateContent({
    contents: [
      {
        role: 'user',
        parts: [
          {
            fileData: {
              fileUri: gcsUri,
              mimeType: 'video/quicktime',
            },
          },
          { text: 'Analyse this cat video and return a JSON result.' },
        ],
      },
    ],
  });

  const candidates = result.response.candidates;
  const parts = candidates?.[0]?.content?.parts ?? [];
  const finishReason = candidates?.[0]?.finishReason;

  // Gemini 2.5 Flash is a thinking model: parts may include reasoning chunks
  // flagged with `thought: true`. Skip those and use the first output part.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const outputPart = parts.find((p: any) => !p.thought);
  const text = outputPart?.text ?? '';

  if (!text) {
    const summary = JSON.stringify({
      candidateCount: candidates?.length ?? 0,
      finishReason,
      partCount: parts.length,
      partTypes: parts.map((p: any) => (p.thought ? 'thought' : 'text')),
    });
    throw new Error(`Empty response from Vertex AI — ${summary}`);
  }

  return text;
}
