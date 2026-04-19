import {
  VertexAI,
  HarmCategory,
  HarmBlockThreshold,
} from '@google-cloud/vertexai';
import { readFileSync } from 'fs';
import { join } from 'path';

const LOCATION = 'us-central1';
const MAX_OUTPUT_TOKENS = 300;

// Verify this model ID at https://cloud.google.com/vertex-ai/generative-ai/docs/learn/models
// Update to the GA Gemini 3.1 Flash model ID once available on Vertex AI.
const MODEL = 'gemini-2.0-flash-001';

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

  const text =
    result.response.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

  if (!text) throw new Error('Empty response from Vertex AI');

  return text;
}
