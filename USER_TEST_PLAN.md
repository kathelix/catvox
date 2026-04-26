# CatVox MVP Early User Test Plan

## 1. Purpose

This session is a lightweight early user test for the CatVox MVP.

The goal is to learn:

1. whether a new user understands what the app is for without heavy explanation;
2. whether they can use it naturally without guidance;
3. where they feel confused, blocked, frustrated, or pleasantly surprised; and
4. whether they show any believable signal of future use.

This is a pretotyping / customer development session, not a formal usability study.

---

## 2. Roles

### 2.1 Facilitator

The facilitator:

1. prepares the device and recording;
2. reads the introduction script;
3. starts screen recording with microphone enabled;
4. remains silent during the test unless a technical issue makes the test impossible to continue;
5. asks the 3 post-test questions;
6. records brief facilitator observations in the same recording; and
7. later reviews the recording with Gemini.

### 2.2 Test user

The test user:

1. uses the app as a first-time user;
2. follows the scenario naturally;
3. thinks aloud during the session; and
4. answers the 3 post-test questions at the end.

---

## 3. Before the session

The facilitator will:

1. ensure the CatVox app is installed and ready on the iPhone;
2. check battery level and available storage;
3. reduce distractions by closing unrelated apps and silencing notifications if possible;
4. prepare a quiet environment so spoken comments are clearly captured; and
5. ensure screen recording is available on the device;
6. enable microphone recording for the screen recording;
7. make sure the user knows that the screen and all spoken comments will be recorded for product learning.

---

## 4. Introduction script

The facilitator will say the following word for word before starting:

> Thanks for trying this. This is an early version of a new app, and I'd like you to use it as naturally as possible. Please imagine you've just opened it because you want to understand what your cat is trying to communicate. As you go, please say out loud what you expect, what you notice, and anything that feels confusing, frustrating, or surprisingly good. I'll stay quiet and won't guide you, because I'm testing the app, not you. I'm going to record the screen and your voice comments so I can review the session afterwards.

---

## 5. Test flow

### Step 1 - Start the session

The facilitator will:

1. ask the user if they are ready;
2. start iPhone screen recording with microphone enabled; and
3. hand the device to the user.

### Step 2 - User explores the app

The user will:

1. use the app naturally;
2. act from this scenario: they have just opened the app because they want to understand what their cat is trying to communicate; and
3. keep talking throughout the session, including what they expect, what they think a screen or button means, what feels easy, and what feels confusing, frustrating, useful, or enjoyable.

### Step 3 - Facilitator observes silently

During the session, the facilitator will:

1. stay quiet;
2. not explain the interface;
3. not suggest what to tap;
4. not correct misunderstandings;
5. not defend the app; and
6. intervene only if a technical problem makes the test impossible to continue, while saying aloud what is being done so the full context remains in the same recording.

### Step 4 - End the exploration

The exploration ends when one of the following happens:

1. the user naturally finishes exploring the app;
2. the user says they are done;
3. the user reaches a clear stopping point; or
4. the session becomes repetitive and no longer produces new observations.

### Step 5 - Ask the post-test questions

Without stopping the recording, the facilitator will ask these 3 questions exactly:

1. What do you think this app is for, in your own words?
2. What was the most confusing, awkward, or frustrating moment?
3. If this app already existed on your phone, in what situation would you actually use it - and would you come back to it?

### Step 6 - Record facilitator observations

Still in the same recording, the facilitator will briefly say:

1. their first impression of what happened;
2. the biggest confusion point;
3. the strongest positive reaction;
4. whether the user seemed to understand the product value;
5. whether this person seems likely to use the app again; and
6. any quote worth preserving verbatim.

### Step 7 - Stop and save the recording

The facilitator will:

1. stop the recording only after the user answers and facilitator observations are spoken;
2. save the screen recording;
3. use a consistent file name; and
4. store it in a consistent location for later review.

Suggested naming format:

`catvox_test_YYYY-MM-DD_userNN.MP4`

Example:

`catvox_test_2026-04-24_user01.MP4`

---

## 6. What to observe

During the session, the facilitator should pay attention to:

1. the first thing the user taps;
2. which paths or screens they use;
3. where they hesitate;
4. where they misunderstand the app;
5. where they backtrack;
6. any spontaneous positive reaction;
7. any sign of delight, curiosity, or emotional connection;
8. any explicit statement of confusion, value, disappointment, or desire; and
9. whether they reach an outcome that feels meaningful to them.

---

## 7. Gemini review guidance

Attach **both** files to Gemini:

1. the produced screen recording; and
2. this `USER_TEST_PLAN.md` file.

Use the prompt below.

### 7.1 Gemini prompt to copy and paste

```text
You are analysing an attached screen recording of a CatVox early user test session.

Also read the attached `USER_TEST_PLAN.md` first and treat it as the authoritative context for this analysis.
In particular, use these sections as ground truth:
- Section 2 - Roles
- Section 5 - Test flow
- Section 6 - What to observe
- Section 7 - Gemini review guidance
- Section 8 - Consistency rules across users
- Section 9 - Success criteria for this phase

Important instructions:

1. Separate the 2 speakers clearly:
   - User
   - Facilitator

2. Both speakers may speak in any language, including English, Russian, or mixed-language speech.
   - Do not assume the audio is only English.
   - Preserve original quotes in the original language where possible.
   - Also provide an English translation for non-English quotes or mixed-language quotes.

3. If speaker identity is uncertain, mark it as `[UNCERTAIN SPEAKER]` instead of guessing.

4. Use the test plan as the source of truth for the session structure and facilitator intent.
   Do not repeat the plan back to me unless needed for the analysis.

5. Treat facilitator comments separately from user feedback.
   - The facilitator introduction is context, not product feedback.
   - Any facilitator observations recorded at the end should be analysed separately from the user's experience.

6. Focus on evidence from:
   - what happened on screen;
   - what the user said;
   - what the facilitator said; and
   - the relationship between user behaviour and facilitator interpretation.

7. Do not invent quotes, motivations, or conclusions that are not supported by the recording.

Please produce the output in English with the following structure.

## 1. Executive summary
Provide a short summary covering:
- whether the user understood what the app is for;
- the main friction points;
- the strongest positive signals;
- whether there is believable repeat-use potential.

## 2. Speaker identification
Briefly explain how you distinguished:
- User
- Facilitator
- any uncertain segments

## 3. Timecoded timeline
Create a table with these columns:
- Time
- Speaker
- Original quote
- English translation
- What happened on screen
- Interpretation
- Labels

Use approximate timestamps if needed.

## 4. User journey reconstruction
Describe step by step:
- first action;
- explored paths;
- retries or backtracking;
- where the user seemed confident;
- where the user seemed lost.

## 5. Top friction points
Rank the most important product or UX problems.
For each one include:
- evidence;
- timestamp(s);
- why it matters.

## 6. Top positive signals
List the strongest moments of:
- delight;
- clarity;
- curiosity;
- perceived value;
- emotional connection.

## 7. Answers to the 3 post-test questions
Extract and summarize the user's answers to the 3 exact questions from the session.
If an answer is incomplete, indirect, or missing, say so.

## 8. Facilitator-only observations
Extract only the facilitator's own observations recorded at the end.
Summarize:
- first impression;
- biggest confusion point;
- strongest positive reaction;
- whether the facilitator thought the user understood the value;
- whether the facilitator thought the user would use the app again;
- any quote worth preserving.

## 9. Comparison: user evidence vs facilitator interpretation
Compare:
- what the user actually did and said;
- what the facilitator believed happened.

Mark clearly:
- where they align;
- where the facilitator may have overestimated something;
- where the facilitator may have underestimated something.

## 10. Product recommendations
Provide a short ranked list of improvements.
For each recommendation include:
- the problem it addresses;
- evidence from the session;
- priority: high / medium / low.

## 11. Final verdict
End with:
- Product understanding: Clear / Partly clear / Unclear
- Navigation usability: Smooth / Mixed / Problematic
- Repeat-use signal: Strong / Weak / None
- Recommendation: Keep testing as-is / Fix top issues first / Reposition product message

Use these labels where relevant:
- Expectation
- Hesitation
- Confusion
- Frustration
- Delight
- Value signal
- Abandonment risk
- Positive usability signal
- Misunderstanding
- Facilitator observation
```

---

## 8. Consistency rules across users

To keep sessions comparable, the facilitator should:

1. use the same introduction every time;
2. use the same scenario every time;
3. remain equally silent in each session;
4. ask the same 3 post-test questions every time;
5. record every session in the same way; and
6. keep a simple cross-user summary of findings.

---

## 9. Success criteria for this phase

This phase is successful if it helps the product team learn:

1. whether users understand what CatVox is for;
2. whether they can use it without being taught;
3. what parts of the experience damage clarity, trust, or interest; and
4. whether users express a believable reason to use it again.

The goal is not polite praise.

The goal is to discover:

1. what the user thinks the app is;
2. what the user actually does; and
3. where reality differs from current product assumptions.
