# CatVox MVP Early User Test Plan

**Version:** 1.0
**Last updated:** 2026-04-27

Increment this version when the user-test procedure, storage workflow, review workflow, or success criteria change.

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
7. later reviews the YouTube-hosted recording with Gemini.

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
7. make sure the user knows that the screen and all spoken comments will be recorded for product learning and uploaded as a Public YouTube video for later review.

---

## 4. Introduction script

The facilitator will say the following word for word before starting:

> Thanks for trying this. This is an early version of a new app, and I'd like you to use it as naturally as possible. Please imagine you've just opened it because you want to understand what your cat is trying to communicate. As you go, please say out loud what you expect, what you notice, and anything that feels confusing, frustrating, or surprisingly good. I'll stay quiet and won't guide you, because I'm testing the app, not you. I'm going to record the screen and your voice comments, then upload the recording as a Public YouTube video so I can review the session afterwards.

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
4. store it in a consistent location for later review;
5. upload the recording to the designated YouTube archive as a Public video; and
6. record the YouTube URL for later Gemini review and research notes.

Suggested naming format:

`catvox_test_YYYY-MM-DD_userNN.MP4`

Example:

`catvox_test_2026-04-24_user01.MP4`

The YouTube title should use the same session identifier without the file extension:

`catvox_test_YYYY-MM-DD_userNN`

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

## 7. Video storage on YouTube

User-test screen recordings are stored in YouTube after each session.

YouTube is used as the working archive for raw session recordings because it provides reliable playback, long-video handling, and easy review links for later analysis.

The facilitator must:

1. upload the saved screen recording to the designated CatVox user-testing YouTube account;
2. use the same session identifier in the YouTube title as the local recording file name;
3. set the video visibility to Public;
4. store the YouTube URL together with the session notes or generated analysis report;
5. after the Gemini analysis is complete, set the video visibility to Private;
6. remove or restrict access to videos if a participant later asks for their session recording to be deleted or no longer used.

Suggested YouTube title format:

`catvox_test_YYYY-MM-DD_userNN`

The local recording file and YouTube title should share the same session identifier.

---

## 8. Gemini review guidance

Use the YouTube-hosted recording as the review source.

To review the session in Gemini:

1. Use the prompt template in `docs/USER_TEST_GEMINI_REVIEW_PROMPT.md`.
2. Copy the full contents of that file into a new Gemini chat.
3. Replace `YOUTUBE_URL_OF_THE_VIDEO` inside the prompt with the actual URL of the uploaded video.
4. Attach this `USER_TEST_PLAN.md` file.
5. Run the prompt.

The generated analysis must include the versions of both `USER_TEST_PLAN.md` and `USER_TEST_GEMINI_REVIEW_PROMPT.md` that were used.

After Gemini responds, save only the content inside the fenced `markdown` block as a private research artifact. Suggested private filename:

`catvox_test_YYYY-MM-DD_userNN_analysis.md`

After the analysis is saved, set the YouTube video visibility to Private as required in Section 7.

Do not commit raw recordings, transcripts, or generated analysis reports unless a later sanitized summary is intentionally prepared for the repo.

### 8.1 Gemini prompt file

The copy-paste prompt is stored separately in `docs/USER_TEST_GEMINI_REVIEW_PROMPT.md`.

---

## 9. Consistency rules across users

To keep sessions comparable, the facilitator should:

1. use the same introduction every time;
2. use the same scenario every time;
3. remain equally silent in each session;
4. ask the same 3 post-test questions every time;
5. record every session in the same way; and
6. keep a simple cross-user summary of findings.

---

## 10. Success criteria for this phase

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
