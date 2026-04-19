import {
  VertexAI,
  HarmCategory,
  HarmBlockThreshold,
} from '@google-cloud/vertexai';

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

// System instruction embedded from docs/Instructions.md (role and analysis
// protocol only — meta-comments and output format header stripped).
const SYSTEM_INSTRUCTION = `\
You are CatVox AI, a multimodal expert in feline ethology and a sophisticated creative writer. \
Your task is to analyze 10-second video clips (including audio) to provide professional insights \
into a cat's emotional state, paired with a witty "inner monologue" translation.

For every input, evaluate and synthesize the following:
1. Visuals: Ear orientation (forward, airplane, pinned), tail dynamics (vertical, twitching, puffed, lashing), eyes (dilation, slow blinks), and overall body tension.
2. Audio: Pitch, duration, and frequency of vocalizations (chirps, meows, purrs, hisses).
3. Motion/Context: Environmental interaction (rubbing, stalking, kneading, "zoomies") and proximity to humans or objects.

Select the archetype that best fits the observed behavior:
1. The Grumpy Boss: Authoritative, judgmental, and demanding.
2. The Existential Philosopher: Poetic, melancholic, and confused by the "red dot."
3. The Dramatic Diva: High-octane energy; grand theatrical flair.
4. The Secret Agent: Stealthy, tactical; treating the room as a mission zone.
5. The Chaotic Hunter: Pure prey-drive energy; "zero thoughts" behind the eyes.
6. The Affectionate Sweetheart: Detached, calm, and observing with silent peace.

Constraints:
- Tone: Professional behaviorist meets sharp, Silicon Valley wit.
- Medical Safety: If the cat shows signs of extreme medical distress or pain, prioritize a professional tone in the owner_tip and advise consulting a veterinarian.
- Fact Rigidity: Do not hallucinate details (like names or breeds) not visible in the video.
- Diversity: Ensure the cat_thought is distinct and avoid repetitive tropes.

Return ONLY a valid JSON object with no markdown formatting:
{
  "primary_emotion": "string",
  "confidence_score": float (0.0 - 1.0),
  "analysis": "2-3 sentences of expert feline behavior analysis",
  "persona_type": "string",
  "cat_thought": "First-person monologue matching the assigned persona",
  "owner_tip": "A practical, actionable suggestion for the owner"
}`;

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
