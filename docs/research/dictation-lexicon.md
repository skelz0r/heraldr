# Research: dictation lexicon

Research from 2026-10-12, no implementation. Starting question:
dictation corrections are not accurate; would the lexicon, kept on the
iPhone today, be better held on the Mac in a real database? This
document covers what others do, what is wrong on our side, and proposes
an iteration order. Nothing here is decided: a decision goes into
`docs/decisions.md`, a behaviour change into `docs/spec.md`.

The current behaviour (spec §4.5, §5.1, §5.2) is not described again
here.

## Conclusion

Storage is not the problem. The problem comes from three points:

- contextual vocabulary is ignored by the transcriber we use;
- the list of pairs given to the small model goes against Apple's
  guidance;
- silent learning is not filtered.

A SQLite database on the Mac would fix none of that, and reading it on
every dictation would add a network dependency: rule it out. The Mac
does have a place as a mirror, so nothing is lost on reinstall and the
list can be edited with a keyboard.

Recommendation:

- organise the lexicon as terms ("Acme") carrying their misheard
  variants ("ack me");
- use the terms to bias recognition, and have the code, not the model,
  replace known variants;
- replace silent learning with suggestions to approve;
- keep the iPhone copy for dictation, with a JSON mirror on the Mac
  synced over SSH on each connection;
- move the list out of Settings into a dedicated page.

## What is wrong on our side

### 1. Contextual vocabulary does nothing today

`Dictation.swift` uses `SpeechTranscriber` when it is available, so
almost always, and passes it the "intended" words as
`contextualStrings[.general]`. Only `DictationTranscriber` takes them
into account:

- `AnalysisContext.contextualStrings` docs: the property is only
  described "with the DictationTranscriber module"
  (<https://developer.apple.com/documentation/speech/analysiscontext/contextualstrings>);
- answers on the Apple forums, September 2025 and January 2026: "The
  SpeechTranscriber module does not currently take contextual strings
  into account"
  (<https://developer.apple.com/forums/thread/801877>,
  <https://developer.apple.com/forums/thread/811083>). The answering
  account is not formally identified as Apple, but the docs point the
  same way;
- a published A/B test on the same audio gets the name "Ibiuna"
  recognised 5 times out of 5 with the bias under
  `DictationTranscriber`, 0 out of 5 without
  (<https://github.com/augustomklee/mach-voice/pull/2>);
- article "iOS 26 didn't kill custom vocabulary, you're adding it to the
  wrong module"
  (<https://dev.to/simple_memo/ios-26-didnt-kill-custom-vocabulary-youre-adding-it-to-the-wrong-module-5bdc>).

The call is made with `try? await analyzer.setContext(context)`: a
rejection would go unnoticed. Check on the iPhone whether `setContext`
throws or accepts and ignores.

The choice has a cost. `SpeechTranscriber` is a new model,
`DictationTranscriber` reuses the system dictation model (WWDC25
session 277, <https://developer.apple.com/videos/play/wwdc2025/277/>).
One is more accurate in general, the other is the only one that can be
biased. Published comparisons only cover English (MacStories:
<https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/>).
Nothing is published for French mixed with technical English: it has to
be measured.

`DictationTranscriber` also accepts a custom language model, through
the content hint `customizedLanguage(modelConfiguration:)` and
`SFCustomLanguageModelData`
(<https://developer.apple.com/documentation/speech/dictationtranscriber/contenthint/customizedlanguage(modelconfiguration:)>,
<https://developer.apple.com/documentation/speech/sfcustomlanguagemodeldata>).
This model allows:

- weighted phrases;
- templates ("create a branch <term>");
- X-SAMPA pronunciations for made-up words like `herdr` or `worktree`.

Apple warns that for such made-up words, without a pronunciation, the
system "may not estimate their pronunciation correctly". `fr_FR`
support has to be checked with `supportedPhonemes(locale:)`. Building
the model takes a non-trivial amount of time (WWDC23 session 10101,
<https://wwdcnotes.com/documentation/wwdc23-10101-customize-ondevice-speech-recognition/>).

Documented limits of contextual strings: 100 phrases at most, one or
two words each preferably.

### 2. The cleanup prompt asks the model for what it does badly

The cleanup passes 20 "heard → intended" pairs, to correct "when the
context fits". For the on-device model (~3 billion parameters, 4096
token context), that is 20 conditional rules, almost none of which
concern the current dictation. Apple says exactly not to do this:

- "too much conditional complexity can affect the on-device model's
  ability to follow instructions"; prefer "programming logic to
  customize the prompt based on known information"
  (<https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model>);
- the model does its best on "a single specific task" and is not
  optimised for code (WWDC25 session 248,
  <https://developer.apple.com/videos/play/wwdc2025/248/>);
- long instructions degrade quality (TN3193,
  <https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window>).

On the research side, LLM correction on text alone makes needless
changes and handles rare words badly, unless it is given phonetic
context or alternative hypotheses
(<https://arxiv.org/abs/2505.17410>). Approaches that work constrain
the model and check its edits in code
(RECOVER, <https://arxiv.org/abs/2603.16411>), or only correct
uncertain spans (<https://arxiv.org/abs/2310.11532>).

Products on the market reach the same conclusion. Wispr Flow sums it
up: "LLMs are phenomenal at recall, but very low precision"
(<https://wisprflow.ai/post/technical-challenges>). Its docs advise
adding an explicit correction when a dictionary word is not enough
(<https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary>).
FreeFlow passes the vocabulary to the LLM and "Claude Code" is still
misspelled (<https://github.com/zachlatta/freeflow/issues/125>).
VoiceInk saw its LLM force a dictionary term where it did not belong
(<https://github.com/Beingpax/VoiceInk/issues/281>).

The starting hypothesis, "the small on-device model applies pairs
listed in a prompt badly", is thus confirmed by Apple's guidance,
research and products. There is no published measurement of a 3B model
applying a list of corrections.

### 3. Learning keeps noise

The diff on send does not tell a mishearing from a rewording: changing
"check" into "verify" produces a pair. The literature has said so for a
long time: "if the learning module blindly learns from all the edits
the user has made, it will gradually corrupt the ASR system"
(Yu et al., Interspeech 2004,
<https://www.isca-archive.org/interspeech_2004/yu04f_interspeech.pdf>).
Google's patents filter edits by edit distance, phonetic similarity and
repetition
(<https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/12340799>).

What makes it worse for us:

- no phonetic proximity filter between heard and intended, only the
  "half of the words changed" threshold;
- a single occurrence is enough, and it goes to the top;
- ranking is by recency, while `count` is stored but unused. The 20
  pairs in the prompt are therefore the 20 latest, not the 20 useful
  ones;
- the kept neighbour word ("on push → git push") makes the pair safer
  for a replacement, but rarer to see again as is;
- a deleted pair can be learned again on the next send.

The rest of the market:

| Product | Learning |
| --- | --- |
| OpenWhispr | silent, with undo; polluted the list (<https://github.com/OpenWhispr/openwhispr/issues/358>), which led to adding a toggle; 28 of a user's 29 words came from auto-learning when their prompt truncated their dictations (<https://github.com/OpenWhispr/openwhispr/issues/2474>) |
| Wispr Flow | only learns spelling changes of a single word (proper nouns, domain terms, acronyms); excludes code, paths, URLs, numbers and common words; never learns a deleted one again (dictionary docs and <https://wisprflow.ai/data-controls>) |
| VoiceInk | has an LLM judge each edit ("phonetic evidence", no semantic rewrite), then checks the verdict in code (<https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/AutoLearn/AutoLearnAIReviewer.swift>); the maintainer admits it "needs more polishing" (<https://github.com/Beingpax/VoiceInk/issues/985>) |
| FluidVoice | the most careful model: a single word, inflections rejected, suggestion shown after 1 to 3 occurrences in 7 days (configurable), 7-day pause after a rejection, no more suggestions after 3 rejections in the session (<https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/AutomaticDictionaryCorrectionTracker.swift>) |

The hypothesis "the diff captures rewordings as much as mishearings" is
not measured on our side, but everyone had to filter.

### 4. 50 / 20 entries: the count is not the problem

Bias lists offered by providers range from 20 to 100 terms. Beyond
that, nearby words trigger wrongly:

| Source | Recommendation or finding |
| --- | --- |
| Deepgram | up to 100 terms, recommends "20-50" (<https://developers.deepgram.com/docs/keyterm>) |
| Google | warns that more boost means more false positives (<https://docs.cloud.google.com/speech-to-text/docs/boost>) |
| TCPGen | gains on biased words are eaten by errors on the others (<https://arxiv.org/abs/2109.00627>) |
| FluidVoice | a large imported list corrupted correct words (<https://github.com/altic-dev/FluidVoice/issues/944>) |

The right count depends on the channel:

- for recognition, ≤ 100 chosen terms;
- for the model, 0 to 3 pairs relevant to the current dictation;
- for code replacement, as many as needed, since only a match
  triggers.

Keeping more than 50 corrections costs nothing if they are not all
given to the model.

## What others do

### Two kinds of entries, three channels

All mature products end up with two lists:

- **terms**, the intended spelling, sent as hints to recognition;
- **replacements** heard → intended, applied by code.

| Product | Terms (hints) | Replacements (code) | LLM |
| --- | --- | --- | --- |
| Wispr Flow (closed) | dictionary, undocumented injection | "Correct a misspelling": whole word, case-insensitive, longest first, case preserved ([docs](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)) | not for free prompts |
| Superwhisper (closed) | "Vocabulary", "keep the list short"; causes hallucinations if too long ([docs](https://superwhisper.com/docs/get-started/interface-vocabulary), [hallucinations](https://superwhisper.com/docs/common-issues/hallucinations)) | "Replacements", "applied programmatically, with no AI interpretation" | depends on mode |
| Aqua Voice (closed) | dictionary; matching "by how they sound" in Japanese since 2026-10-06 ([changelog](https://aquavoice.com/changelog)) | snippets, "Preserve case" | free instructions |
| MacWhisper (closed) | words corrected only when an AI prompt is active ([release notes](https://macwhisper-site.vercel.app/release_notes.html), unofficial mirror) | "Global Replace", case-sensitive or not ([docs](https://docs.macwhisper.com/article/37-find-and-replace-in-transcriptions)) | yes |
| VoiceInk (Swift, open) | cloud API keyterms; removed from the Whisper prompt ([#250](https://github.com/Beingpax/VoiceInk/issues/250)) | regex with Unicode boundaries, longest first, comma-separated variants ([WordReplacementService.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/Workflows/WordReplacementService.swift)) | "Do not force a replacement when the text clearly means something else" ([AIEnhancementService.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift#L152-L165)) |
| FluidVoice (Swift, open) | Parakeet CTC boosting, 256 terms max ([ParakeetVocabularyStore.swift](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ParakeetVocabularyStore.swift)) | regex, longest first, guard against re-expansion ([ASRService.swift](https://github.com/altic-dev/FluidVoice/blob/main/Sources/Fluid/Services/ASRService.swift#L7479-L7531)) | no dictionary |
| OpenWhispr (Electron, open) | Whisper `initial_prompt` and keyterms; per-provider caps ([dictionaryPromptCap.js](https://github.com/OpenWhispr/openwhispr/blob/main/src/utils/dictionaryPromptCap.js)) | snippets only | list appended without a cap |
| Handy (Rust, open) | `initial_prompt` for Whisper | fuzzy Levenshtein × Soundex matching, ASCII only ([text.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/audio_toolkit/text.rs#L79-L235)) | no |

Lessons from the issue trackers:

- **Whisper prompt**: the most fragile channel. At OpenWhispr, silence
  returns the whole dictionary ([#842](https://github.com/OpenWhispr/openwhispr/issues/842)),
  the prompt text gets repeated ([#2581](https://github.com/OpenWhispr/openwhispr/issues/2581)),
  a long dictation gets truncated ([#2474](https://github.com/OpenWhispr/openwhispr/issues/2474)).
  Not relevant for us, but it is the equivalent of overloading the
  bias.
- **Code replacement**: the most reliable channel, provided it is done
  right:
  - Unicode word boundaries, not ASCII `\b`: VoiceInk replaced inside
    "vergrößern" ([#756](https://github.com/Beingpax/VoiceInk/issues/756));
  - longest first;
  - cycle detection;
  - allow case-only corrections, `iphone → iPhone`
    ([#961](https://github.com/Beingpax/VoiceInk/issues/961)).
- **Replacement false positives**, the reason for our initial refusal:
  they come from short, common heard forms. At FluidVoice,
  `sean → Shaun` also changed "mean"
  ([#880](https://github.com/altic-dev/FluidVoice/issues/880)), because
  boosting pulled towards nearby words. At Handy, truncated Soundex
  turned "Son of" into "Shinobi"
  ([#1333](https://github.com/cjpais/Handy/issues/1333),
  [#2099](https://github.com/cjpais/Handy/pull/2099)). An exact
  multi-word replacement, like our "on push → git push", does not have
  this problem.
- **Coded phonetic matching**: weak everywhere. French algorithms
  (Phonex, Soundex2, FONEM,
  <https://abydos.readthedocs.io/en/latest/_modules/abydos/phonetic/_fonem.html>)
  are made for surnames. None models English pronounced the French way
  ("ouorktri" → worktree). Useful to filter or pick candidates, not to
  replace unchecked.

### Wispr Flow in detail

Market reference, closed, transcription always in the cloud
(<https://wisprflow.ai/data-controls>):

- **Model**: a single word, or a "Correct a misspelling" pair. Snippets
  (spoken trigger → block of text) and per-app-category styles are
  separate. Styles only apply in English
  (<https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles>).
- **Adding**:
  - by hand;
  - from history ("Add to vocabulary → Correct a misspelling");
  - CSV import, 1,000 entries per file
    (<https://docs.wisprflow.ai/articles/8955301725-how-do-i-bulk-import-for-dictionary-and-snippets>);
  - team sharing;
  - "Auto-add to Dictionary", which watches the field the text was
    pasted into and keeps a spelling change, with no documented
    confirmation.
- **Priority**: since 2026-03-31, a word can be starred to get priority
  in transcription, and the list is sorted by usage
  (<https://wisprflow.ai/whats-new>). This suggests the list sent to
  recognition is capped; that is an inference.
- **Context**: app category, text around the cursor, names on screen,
  variable and file names in code editors
  (<https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness>).
- **Storage**: cloud account, synced across devices regardless of the
  history sync setting.
- **UI**: dedicated page, search (except on iOS), sort by star,
  recency, alphabet or usage, bulk delete. An "Insights" page shows the
  replacements made and the most corrected word.
- **Languages**: one language per dictation, no code-switching;
  replacements do not depend on the language
  (<https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages>).

A third-party tool reads Wispr's local history to find misheard words
and add corrections in bulk
(<https://github.com/yahyabedirhan/skills/issues/33>). A sign that
auto-learning is not enough for product and command names.

### Apple, for comparison

Voice Control on the Mac accepts 1,000 terms per language, with
recorded pronunciation and text import/export, but no API
(<https://support.apple.com/guide/mac-help/mchl3eb7b79a/mac>). iOS
dictation has no user dictionary.

## Where to store the lexicon

| Option | Pros | Cons |
| --- | --- | --- |
| iPhone only (today, UserDefaults) | offline dictation, even before the SSH connection; no latency; nothing to install on the Mac | no backup outside the iPhone; not editable elsewhere |
| Mac as source of truth (SQLite or file), read over SSH on each dictation | editable with a keyboard, by Claude, versionable, shareable with other Mac tools | dictation depends on the Mac being reachable (LAN/Tailscale); SSH command latency at start; new `dispatch.sh` command, so a new contract to test on both sides; `sqlite3` in shell for a few hundred rows |
| iPhone for dictation, JSON mirror on the Mac synced on each SSH connection | local dictation; survives a reinstall; list editable with a keyboard or by Claude | two more `dispatch.sh` commands; merge to write (dates and tombstones) |
| iCloud (KVS or CloudKit) | Apple backup and sync without the Mac | no second Apple device uses it today; CloudKit needs container setup |
| iPhone as source of truth, plus export/import | backup and editing when needed, no dependency for dictation | manual step |

Volume is in the hundreds of entries: a database is oversized, and it
solves none of the four problems above. The real need is elsewhere:
lose nothing on uninstall. The lexicon lives in UserDefaults, erased
with the app, like `PairedMac`: a reinstall already requires pairing
the Mac again.

Recommendation: a mirror on the Mac, not a source of truth.

- **Local first**: the iPhone keeps its copy, and dictation never reads
  the Mac. It works offline and without latency.
- **A file, not a database**: `~/.config/heraldr/lexique.json` on the
  Mac, next to the APNs key. Versioned JSON, in the format of the app's
  local file, which moves from UserDefaults to Application Support.
  VoiceInk does the same with its `voiceink.dictionary` format
  ([DictionaryArchive.swift](https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Dictionary/Workflows/DictionaryArchive.swift#L3-L43)).
- **Two `dispatch.sh` commands**: `lexicon-get` (the file on standard
  output, empty if missing) and `lexicon-put` (read from standard
  input, written through a temporary file then `mv`). No daemon, no
  port. Two more subcommands in the contract tested in
  `mac/test/dispatch_test.sh`.
- **When to sync**: on every SSH connection the app already opens
  (status, send), in the background. If the local lexicon changed since
  the last sync, the app reads, merges and writes back. Right after
  pairing, the first sync brings everything back: that covers the
  reinstall case.
- **Per-entry merge**: each entry carries `updatedAt`; a deletion
  leaves a tombstone, which the learning step needs anyway so it does
  not learn again what was deleted. Latest wins. The file can then be
  edited on the Mac, by hand or by Claude (add twenty domain terms at
  once), and the iPhone picks it up on the next connection.

The iCloud alternative (`NSUbiquitousKeyValueStore`, 1 MB) also
survives a reinstall and needs no code on the Mac. It does require
adding the iCloud entitlement, absent today, and the list cannot be
edited with the Mac keyboard. The Mac mirror wins because it also
serves to feed domain terms.

## Domain terms

Real-world kind of example: a product name "Acme" transcribed as
"ack me". This is a term, an intended spelling, with misheard variants
attached. Mature products model it this way: one target and several
triggers (`triggers[]` at FluidVoice, comma-separated variants at
VoiceInk). Superwhisper and Aqua advise adding each misheard variant.
Proposed model: one entry = one intended form ("Acme") + its known
heard forms ("ack me", "acne") + its origin (typed, learned, imported,
workspace). Current corrections become heard forms attached to their
intended form.

Three levers, from safest to least certain:

1. **Code replacement of a known heard form**: "ack me" is two words
   that rarely show up by chance in a request, which makes it a safe
   replacement (step 2). It only covers variants already seen.
2. **Recognition bias**: the term in `contextualStrings`, and if
   `fr_FR` allows it, a custom language model with its X-SAMPA
   pronunciation. Only `DictationTranscriber` benefits: that is the
   spike's purpose (step 1). It is the only lever that avoids the
   error instead of repairing it.
3. **Phonetic matching of a never-seen variant**: compare groups of 1
   to 3 words from the transcription, joined ("ackme"), with the terms.
   Handy does this
   ([text.rs](https://github.com/cjpais/Handy/blob/main/src-tauri/src/audio_toolkit/text.rs#L79-L235)).
   Raw edit distance is not enough: "ackme" against "acme" gives 1 in
   5, above Handy's 0.18 threshold, while English Soundex, built for
   surnames, knows nothing of English words pronounced the French way.
   It takes a French phonetic key tuned on the corpus. A match must not
   replace directly: it offers the term to the model as the only
   candidate, or in the preview.

Where terms come from:

- typing and bulk import: the file on the Mac (previous section) fits;
- what the app already knows without asking: herdr workspace and tab
  labels, agent names. Wispr likewise reads file and variable names in
  editors
  (<https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness>);
- learning, when the intended form of a correction looks like a proper
  noun or a technical term.

Typed or imported terms come first in the 100 slots of the recognition
bias. The others take what is left, by usage.

## UI: a dedicated page

What recurs elsewhere:

| Feature | Examples |
| --- | --- |
| separate page, search | Wispr, OpenWhispr, FluidVoice; missing search is an open issue at VoiceInk ([#654](https://github.com/Beingpax/VoiceInk/issues/654)) |
| sort by recency or usage | Wispr; usage is requested at OpenWhispr ([#399](https://github.com/OpenWhispr/openwhispr/issues/399)) |
| priority mark | star at Wispr |
| visible origin (learned or typed) | `source` column at OpenWhispr; requested at VoiceInk ([#965](https://github.com/Beingpax/VoiceInk/issues/965)) |
| suggestions to approve | FluidVoice, VoiceInk's "Manually" mode, Dragon's assistants |
| add from a transcription | Wispr (history), Voice Control's "Add to vocabulary" |
| statistics | Wispr's "Insights" |

For Heraldr, a "Lexicon" page, opened from the home screen or from a
dictation preview rather than deep in Settings, with two sections:

- **To review**: learned suggestions, each with the sentence it came
  from; "Keep" or "Ignore"; a rejection is never offered again;
- **Terms**: the intended spelling and its heard variants, number of
  applications, origin; a star sends the term first to the recognition
  bias.

Plus search, and in the preview, a "tap a word → Correct" gesture that
creates an explicit correction. That is noise-free learning, since the
intent is clear.

The "Keep X → Y?" confirmation had been ruled out (decisions.md), but
it was a question asked on send, which interrupted. A list to review
later, shown only after two occurrences, does not have that cost.

## Iteration plan

Each step ships on its own and is measurable. Steps 1, 2 and 4 target
"not accurate" directly, 3 protects against loss, 5 keeps it from
degrading again, 6 is comfort.

**0. Measure before changing**

- Keep for each sent dictation: the raw transcription, the cleaned text
  and the sent text. The history and "Show original" already hold part
  of it.
- Add an export of all of it.
- Build a set of 20 to 30 real recorded dictations, with the terms
  that cause trouble (herdr, worktree, Claude, branch names).
- Criterion: rate of lexicon terms spelled right before any manual
  edit.
- Without this corpus, there is no telling whether a step helps.

**1. Transcriber spike** (result in `docs/risks.md`)

- Check that `setContext` has no effect on `SpeechTranscriber`. Remove
  the silent `try?`, or at least log the error.
- On the corpus, compare:
  - `SpeechTranscriber` without bias;
  - `DictationTranscriber` with ≤ 100 terms;
  - `DictationTranscriber` with a custom language model (X-SAMPA
    pronunciations for herdr, worktree; templates) if `fr_FR` allows
    it.
- Also test the `alternativeTranscriptions` and
  `transcriptionConfidence` options of `SpeechTranscriber`
  (<https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption>),
  which could target correction at uncertain spans.
- Decision to make: which transcriber. If `SpeechTranscriber` wins,
  stop passing it a vocabulary it ignores.

**2. Terms and variants, replaced by code**

- New model: an intended form, its heard forms, its origin,
  `updatedAt`, tombstones. Stored as versioned JSON in Application
  Support. Current corrections are migrated into heard forms.
- Replace known heard forms in code, after cleanup: whole words,
  case- and accent-insensitive, longest first, intended form's case
  kept.
- To limit the false positives that got this option ruled out, only
  apply automatically a safe heard form:
  - of two words or more ("ack me");
  - or a single word that is not a common French word;
  - or explicitly approved.
- For the others, give the model only the 0 to 3 pairs whose heard
  form appears in the transcription, phrased about the dictation
  ("here, X probably means Y"), instead of the 20 latest. Stricter
  variant: a `@Generable` that returns the list of substitutions kept
  among these candidates, applied and checked by code.
- This change revisits the decision "deterministic text replacement
  ruled out (false positives)": record it in `docs/decisions.md` and
  spec §5.1 if adopted.

**3. Mirror on the Mac**

- `dispatch.sh lexicon-get` / `lexicon-put`, file
  `~/.config/heraldr/lexique.json`, contract tests on both sides.
- Background sync on each SSH connection, per-entry merge. Right after
  pairing, the first sync restores everything.
- Can come before step 2 if losing the lexicon is pressing: versioned
  JSON absorbs the model change.

**4. Domain terms**

- Terms drawn from herdr workspaces, tabs and agents; bulk import
  through the Mac file.
- Phonetic matching of never-seen variants (French phonetic key plus
  edit distance, threshold tuned on the corpus), offered to the model
  as the only candidate, never replaced outright.

**5. Learning as suggestions**

- A substitution detected on send becomes a candidate, not an entry.
- Filters:
  - keep the rewrite threshold;
  - add phonetic or spelling similarity between heard and intended
    (normalised edit distance, tuned on the step 0 corpus), which rules
    out "check → verify";
  - exclude numbers and paths.
- A candidate seen twice moves to "To review". An explicit correction
  ("Correct" gesture in the preview, or typed) goes straight in.
- Tombstones prevent learning again what was deleted or rejected.
- Rank by usage (`count`, last application) rather than recency. Raise
  the cap, since only the recognition channel is limited (≤ 100).

**6. "Lexicon" page**

- To review / Terms sections, each term with its variants, search,
  counters, star.
- Reached from the home screen and the preview, "Correct" gesture on a
  word.

**7. Later, if the need appears**

- iCloud sync if a second Apple device dictates.

## Open questions

- Actual behaviour of `setContext` on `SpeechTranscriber` in iOS 26
  (throws or ignores).
- `fr_FR` support in custom language models and accepted phonemes.
- Compared accuracy of the two transcribers on French mixed with
  English: no published measurement.
- Reliability of `transcriptionConfidence` on technical terms.
- Exact bias mechanism at Wispr Flow, undocumented.
- Reddit user feedback not consulted: site unreachable during the
  research.
