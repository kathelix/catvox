# CatVox Privacy Policy

> **Draft for review — not published.** Resolve every **[PLACEHOLDER …]** and remove this notice before the page goes live. The checklist is in this folder's `README.md`.

**Last updated:** **[PLACEHOLDER Q12: date the policy takes effect]**

CatVox is an iPhone app that reads your cat's mood and behaviour from a short video. It's made by Kathelix Ltd. This policy explains what CatVox collects, why, who helps us run it, how long we keep data, and the choices you have.

## The short version

- **No account.** CatVox doesn't ask for your name, email address or phone number.
- **Your clip goes to Google for analysis.** When you scan, the video and its sound are uploaded to Google Cloud in the United States and analysed by Google's Gemini AI model. The clip is deleted automatically once it's a day old. **[PLACEHOLDER Q4: accurate only once soft delete is turned off for clip storage. Otherwise: "…once it's a day old, and erased for good about a week after that."]**
- **Your history stays on your iPhone.** Saved scans live only on your phone, and you can delete them at any time.
- **Analytics, not advertising.** We use PostHog to see how CatVox is used, for example how many scans succeed and roughly where our users are. We never send it your videos or the text CatVox writes about your cat, and you can turn analytics off. **[PLACEHOLDER Q8: true only once the analytics opt-out (P26) ships]**
- **No ads, no tracking, no selling.** CatVox shows no ads, doesn't track you across other companies' apps or websites, and we never sell your data.
- **Insight and fun, not veterinary advice.** CatVox's results come from AI and can be wrong.

## Who we are

Kathelix Ltd ("Kathelix", "we", "us") makes CatVox and is the controller of the personal data described in this policy. Kathelix Ltd is registered in **[PLACEHOLDER Q2: England and Wales, or Scotland]** with company number **[PLACEHOLDER Q2: company number]**. Our registered office is **[PLACEHOLDER Q2: registered office address]**.

Email us about privacy at [catvox@kathelix.com](mailto:catvox@kathelix.com).

**[PLACEHOLDER Q11: if Kathelix appoints an EU representative under Article 27 of the EU GDPR, name them and their contact details here; otherwise delete this line]**

## What CatVox collects and why

### The clips you analyse

When you ask CatVox to read your cat, it uploads the clip you recorded or picked: up to 10 seconds of video, with its sound.

- **How it travels.** The app sends the clip over an encrypted connection straight to private storage in Google Cloud in the United States, using an upload link that expires after 15 minutes. Our server then asks Google's Gemini AI model, running on Google Cloud, to analyse it, and sends the result back to your iPhone. We don't keep a copy of your result on our servers.
- **What a clip can contain.** A clip can capture more than your cat: people, voices and your home. Please don't analyse clips of people who haven't agreed to it, especially children.
- **Information stored inside the file.** A video you pick from your Photos library is uploaded as iOS provides it, so any details stored inside the file go with it. These can include when the video was recorded and, if your camera saved it, where. CatVox doesn't use them. Clips you record in CatVox don't include your location.
- **How we use it.** We use your clip only to produce your result. Google's terms for this service don't allow Google to use your clip to train or fine-tune AI models without our permission, and we don't give it. If Google's automated safety systems flag a request as possibly breaking Google's usage policies, Google may keep a record of it for up to 90 days so that authorised Google staff can review it.
- **How long we keep it.** Our storage deletes each clip automatically once it's a day old. Google carries out these deletions in the background, so a clip can occasionally last a little longer. **[PLACEHOLDER Q4a: if soft delete stays on for clip storage, add: "Google Cloud then keeps a deleted clip recoverable by our administrators for 7 more days before erasing it." Delete this note once soft delete is off.]** **[PLACEHOLDER Q4b: if Gemini's response caching stays on, add: "Google may also keep a temporary copy of the request and its result for up to 24 hours to speed up processing." Delete this note once caching is off.]**

### Your install ID and daily scan count

The first time you open CatVox, it creates a random code, your **install ID**, and stores it on your iPhone. It's random: it isn't based on your name, your Apple Account or anything about your iPhone, and it isn't an advertising identifier. Deleting CatVox deletes it, and reinstalling creates a new one. If you restore your iPhone from a backup, the backup brings back the same install ID.

CatVox sends the install ID with each scan so our server can apply the free daily limit of five scans and prevent abuse. For each install ID, the server keeps a small **usage record** in Google Cloud Firestore in the United States. It holds:

- a count of your scans for the day, and the date of your most recent scan;
- while a scan is in progress, a temporary entry with a scrambled (hashed) reference to the upload and the time it started.

We keep the usage record while you use CatVox. **[PLACEHOLDER Q6: "Records with no scans for N days are deleted automatically." Publish this sentence only once the automatic deletion (audit item H6) is live.]**

### Product analytics (PostHog)

We use PostHog, a product analytics service, to understand how CatVox is used, find problems and improve the app. CatVox sends PostHog a short message, called an event, when certain things happen: for example, when you start a recording, pick a clip from Photos, a clip is rejected for being too long, an analysis succeeds or fails, you reach the daily limit, or you share a result.

Each event can include:

- your install ID, plus random IDs that PostHog's software creates on your iPhone, for example to group events into sessions;
- details about what happened, such as where the clip came from, why it was rejected, a description of an error, a random ID for the scan, and a result's short labels: the persona, the main emotion and the confidence score;
- technical details that PostHog's software adds, such as CatVox's version, your iPhone model, iOS version, screen size, language and time-zone settings, and whether you're on Wi-Fi or mobile data.

**Your IP address and approximate location.** Like any internet service, PostHog receives your IP address when CatVox sends it an event. PostHog uses it to estimate your approximate location, such as your city, region and country, and adds that to the event and to your analytics profile. We use this to understand where CatVox's users are, for example to decide which languages to support.

CatVox never sends PostHog your videos or their sound, the text CatVox writes about your cat (the analysis, the cat's "thought" or the tip), file names, or anything from your Photos library. PostHog's automatic tap tracking, session recording, screen-view tracking, crash reporting and surveys are all switched off.

**[PLACEHOLDER Q8: "You can turn analytics off at any time in CatVox under …" Wording and location come from the analytics opt-out (plan item P26), which must ship before this policy is published.]**

PostHog deletes analytics events after one year on our current plan **[PLACEHOLDER Q6: confirm the PostHog plan; pay-as-you-go plans keep events for two years]**. The analytics profile that links events to your install ID stays until we delete it **[PLACEHOLDER Q6: or "until it has had no activity for N months", if we schedule a clean-up]**.

### Technical information our servers receive

Like any internet service, our servers receive your IP address and basic technical details, such as the type of software making the request, every time CatVox contacts them. Google Cloud records these in standard request logs. Our own error logs can also contain a description of the error and, if the AI sends back a malformed answer, the clip's storage name and a short excerpt of that answer. We use logs only to run, secure and fix the service, and Google Cloud deletes them after 30 days.

To stop abuse, CatVox uses Apple's App Attest and Google's Firebase App Check to confirm that requests come from a genuine copy of CatVox on a real iPhone. App Attest produces a cryptographic proof that the app is genuine. App Check verifies that proof without keeping it, then gives the app a short-lived token to send with each request.

### If you contact us

If you email us, we use your email address and your message to reply and help you. We keep support emails for **[PLACEHOLDER Q10: retention period, e.g. two years after the conversation ends]**, unless you ask us to delete them sooner.

### What stays on your iPhone

Your scan history, meaning each clip, its thumbnail and its result, is stored only inside CatVox on your iPhone. We can't see it. Share videos are made on your iPhone too, and go only where you send or save them.

- **To delete a scan,** tap the trash icon next to it in your history, then tap **Delete**. This removes CatVox's copy of the clip, its thumbnail, its result and any share video made from it. It doesn't delete the original video in your Photos library.
- **To delete everything,** delete the CatVox app. That removes all of its data from your iPhone, including your install ID.

Like other app data, CatVox's data can be included in your iPhone's backups, such as iCloud Backup. Those backups are handled by Apple or your computer, not by us.

CatVox asks for permission to use your camera and microphone, so it can record clips, and for permission to add videos to your Photos library, which it uses only when you save a share video. It doesn't need access to your whole Photos library: when you pick a clip, iOS gives CatVox only that clip. CatVox never asks for your location.

## What CatVox doesn't do

- No ads, and no advertising identifiers.
- No tracking across other companies' apps or websites, and no data brokers. We don't let any other company use CatVox to collect information about your activity on other apps or websites.
- We never sell your personal data or share it for advertising.
- No automated decisions about you. CatVox's AI describes your cat's behaviour; it doesn't make decisions about you that have legal or similarly significant effects.

## About CatVox's results

CatVox's results are generated by AI as behavioural insight and entertainment. They can be wrong, and they aren't veterinary advice, a diagnosis or a treatment. If you're worried about your cat's health or behaviour, please talk to a vet.

## Our legal bases

UK and EU data protection law (the UK GDPR and the EU GDPR) requires us to have a legal basis for each use of personal data. Ours are:

| What we do | Legal basis |
|---|---|
| Analyse the clips you submit and send you the results | Contract: it's the service you ask CatVox for |
| Apply the free daily limit, prevent abuse and keep the service secure, using your install ID, usage record, server logs and App Check | Legitimate interests: keeping a free service available and secure |
| Product analytics | **[PLACEHOLDER Q8: "Legitimate interests: understanding and improving CatVox; you can opt out at any time", or "Consent", depending on the analytics choice made for plan item P26]** |
| Replying when you contact us | Legitimate interests: helping you |
| Meeting legal obligations | Legal obligation |

You don't have to give us any personal data, but CatVox can't analyse a clip without uploading it.

## Who we share data with

We don't sell or rent your data. We share it only with the service providers below, which run parts of CatVox for us. Their terms require them to use it only to provide their service to us, and to protect it at least as well as this policy does. **[PLACEHOLDER Q11: true for PostHog only once its data processing agreement is countersigned]**

| Provider | What it does for CatVox | Data involved | Where |
|---|---|---|---|
| Google Cloud | Runs our servers, stores clips and usage records, analyses clips with its Gemini AI models, and keeps our server logs | Clips, install ID, usage record, IP address and logs | United States; server logs on Google's global infrastructure |
| Firebase App Check (Google) | Confirms that requests come from a genuine copy of CatVox | The App Attest proof, which it checks but doesn't keep, and short-lived tokens | Google's global infrastructure |
| PostHog | Product analytics | Analytics events, install ID, device details, IP address and the approximate location PostHog estimates from it | United States |
| Google Workspace | Our email, if you contact us | Your email address and messages | Google's global infrastructure |

We may also disclose data if the law requires it, or to protect the rights, safety or property of CatVox users, Kathelix or others. If Kathelix's business is sold or reorganised, your data would move with it and stay protected by this policy.

Apple distributes CatVox through the App Store and provides App Attest. If you've chosen to share analytics with app developers in your iPhone's settings, Apple also gives us crash reports and statistics about how CatVox performs. Apple's own privacy policy covers the data Apple handles.

## International transfers

Kathelix is based in the United Kingdom, but CatVox's service providers process data in the United States. Google Cloud runs our servers and clip storage in its `us-central1` region (Iowa), analyses clips in the United States **[PLACEHOLDER Q13: true only while the Gemini upgrade (plan item P11) uses a US location, such as `us-central1` or the `us` multi-region; Google's `global` endpoint can process requests anywhere]**, and keeps usage records in its `nam5` multi-region in the United States. PostHog's US Cloud hosts our analytics. Some supporting services, such as Firebase App Check, our server logs and our email, run on Google's global infrastructure and may process data in other countries.

When UK or EU data protection law applies to these transfers, they're protected by the EU–US Data Privacy Framework and its UK Extension, under which Google and PostHog are both certified, and by the Standard Contractual Clauses in their data processing terms. **[PLACEHOLDER Q11: true for PostHog only once its data processing agreement has been generated and countersigned in the PostHog app; Google's terms apply automatically.]** Contact us if you'd like more detail.

## How long we keep data

| Data | Where it's kept | How long |
|---|---|---|
| Clips you analyse | Google Cloud, United States | Deleted automatically once a day old **[PLACEHOLDER Q4: add "then recoverable for 7 more days" if soft delete stays on]** |
| Your results and scan history | Your iPhone only | Until you delete the scan or the app |
| Install ID | Your iPhone | Until you delete the app |
| Usage record | Google Cloud, United States | **[PLACEHOLDER Q6: while you use CatVox, and deleted after N days with no scans]** |
| Analytics events | PostHog, United States | Deleted after one year **[PLACEHOLDER Q6: confirm plan]**; the profile linking them to your install ID stays until we delete it |
| Server logs | Google Cloud | Deleted after 30 days |
| Support emails | Our email | **[PLACEHOLDER Q10: retention period]** |

## Your rights

If you're in the UK or the European Economic Area, you have the right to:

- **access** the personal data we hold about you and get a copy;
- **correct** it if it's wrong;
- **delete** it;
- **restrict** how we use it, or **object** to how we use it, including for analytics;
- **move** it to another service, where that applies;
- **withdraw your consent** at any time, where we rely on consent.

To use any of these rights, email [catvox@kathelix.com](mailto:catvox@kathelix.com). We'll reply within one month, free of charge.

**We need your install ID to find your data.** CatVox doesn't know who you are, so the only way we can match data on our servers to you is your install ID. You can see and copy it in **[PLACEHOLDER Q7: e.g. CatVox → About (plan item P25)]**. Please include it in your email. We won't ask for more information than we need to find your data.

You can also complain to the Information Commissioner's Office (ICO), the UK's data protection regulator, at [ico.org.uk](https://ico.org.uk), or to the data protection authority where you live. We'd appreciate the chance to sort out your concern first.

## Deleting your data

- **On your iPhone:** delete scans one by one in CatVox, or delete the app to remove everything, including your install ID.
- **Clips on our servers:** these are deleted automatically, so you don't need to do anything.
- **Usage record and analytics:** email us your install ID **before** you delete the app, and we'll delete your usage record and your analytics events at PostHog within one month. Once the app is gone, so is your install ID, and we can no longer link those records to you. **[PLACEHOLDER Q6: "Your usage record is then deleted automatically after N days without scans."]** Analytics events are deleted when PostHog's retention period ends.

## US state privacy rights

If you live in California or another US state with a consumer privacy law, you can ask to know, correct or delete the personal information we hold about you, using the steps above. We won't treat you differently for doing so. We don't sell personal information, we don't share it for cross-context behavioural advertising, and we don't use sensitive personal information to infer anything about you.

**Do Not Track.** CatVox doesn't track you across other companies' websites or apps, so it doesn't respond differently to "Do Not Track" signals.

## Children

CatVox is for adults aged **[PLACEHOLDER Q9: 18]** and over. It isn't directed at children, and we don't knowingly collect personal data from anyone under that age. CatVox doesn't ask anyone for their name, age or contact details. If you think someone under that age has sent us personal data, for example by emailing us, contact us and we'll delete it.

## Security and data breaches

We protect your data in ways that suit a small app like CatVox:

- Data travels between the app and our services over encrypted connections (HTTPS).
- Google Cloud encrypts stored data by default.
- Clip storage is private. Each upload link works only for that one clip and expires after 15 minutes.
- Our servers accept requests only from genuine copies of CatVox, checked with App Attest and App Check.
- Access to the systems that run CatVox is limited to Kathelix and the service providers listed above.

No system is perfectly secure. If a personal data breach is likely to put your rights at risk, we'll report it to the ICO within 72 hours of becoming aware of it, as the law requires. If the risk to you is high, we'll also tell you without undue delay. CatVox doesn't collect contact details, so we'll do that on this page and, where we can, in the app.

## Changes to this policy

We'll update this policy when CatVox changes how it handles data, and change the date at the top. If a change is significant, for example if CatVox starts collecting a new kind of data or uses a new service provider, we'll tell you before it takes effect, in the app or on this page, and ask for your consent again where the law requires it. Earlier versions of this policy are in its [public change history](https://github.com/kathelix/catvox/commits/main/docs/public-site/privacy.md).

## About this website

This website is hosted on GitHub Pages. GitHub logs visitors' IP addresses for security purposes, as [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) explains. These pages use no cookies or analytics of their own.

## Contact us

- **Company:** Kathelix Ltd, **[PLACEHOLDER Q2: registered office address]**
- **Email:** [catvox@kathelix.com](mailto:catvox@kathelix.com)
