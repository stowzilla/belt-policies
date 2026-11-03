# AGENTS.md — belt-policies

For agents (and humans) working **on this gem**. To *use* it in a Belt app,
read [README.md](README.md).

## Not legal advice. Keep it that way

This gem must never present itself as providing legal content. Templates are
outlines: headings plus `TODO:` prompts naming topics. Don't add model
policy text, "standard clauses", or claims about what a law requires. Every
user-facing entry point (generator output, `--help`, README, generated files)
carries the `Belt::Policies::NOT_LEGAL_ADVICE` notice. Keep it there.

## Layout

```
lib/
├── belt-policies.rb                    # require shim
├── belt/policies.rb                    # public API: current, accept!, status_for, publish!, …
├── belt/policies/
│   ├── document.rb                     # one policies/<slug>.md (front matter + body)
│   ├── catalog.rb                      # built-in kinds (titles, sections, prompts)
│   ├── publisher.rb                    # policies/*.md → policy_versions (idempotent)
│   ├── release.rb                      # `belt policies publish`: new version + db/migrate file
│   ├── version_record.rb               # mixed into the app's PolicyVersion model
│   ├── acceptance_record.rb            # mixed into the app's PolicyAcceptance model
│   ├── controller.rb                   # index/show/status/accept actions
│   ├── require_acceptance.rb           # before_action guard
│   └── templates/                      # ERB copied into apps
├── belt/generators/policies_generator.rb   # belt g policies (install)
├── belt/generators/policy_generator.rb     # belt g policy <kind>
└── belt/commands/policies_command.rb       # belt policies list|kinds|publish
```

## Design rules

- **Models live in the app**, not the gem. `belt setup tables` builds
  `dynamodb.tf` by reading `lambda/models/*.rb` with regexes. The generated
  model files must keep a literal `class X < ApplicationRecord` and a
  single-quoted `indexes(...)` call.
- **The gem talks to models through a few class methods**: `find_version`,
  `all_versions`, `create_version!`, `for_user`, `record!`. Specs use
  in-memory fakes of exactly those (`spec/support/fake_models.rb`). Add a
  method to the record concern and the fake together.
- **Published text is immutable.** `Publisher` never overwrites a version. It
  reports `:changed`. `Release` writes a new version.
- **Publishing happens in data migrations** (`belt db:migrate`, run by
  `belt deploy`), so every environment gets the same versions with no extra
  deploy hook. Each migration just calls `Belt::Policies.publish!`, which is
  idempotent.
- **Acceptance rows are append-only**, apart from `account_deleted_at`.

## Workflow

```bash
bundle install
bundle exec rspec
bundle exec rubocop    # CI blocks on offenses
```

Try it in a scratch app:

```bash
belt new demo && cd demo
echo 'gem "belt-policies", path: "../belt-policies"' >> Gemfile && bundle
bundle exec belt g policies --with tos,privacy
bundle exec belt policies list
```

User-facing changes go in `CHANGELOG.md`. Bumping
`lib/belt/policies/version.rb` on `master` releases to RubyGems
(`.github/workflows/auto-tag.yml`). Don't bump without a release decision.

<!-- feature-parity:begin -->
## FeatureParity (this project tracks feature parity)

This repo is tracked by [FeatureParity](https://featureparity.dev) as project
**`belt-policies`** (see `.featureparity.yml`). Requirements are shared across every
surface the product ships on, and CI enforces that they stay covered — a pull request
that lets a covered requirement go red will fail the `Parity gate` check.

Two things are expected of you on every change, not just when someone asks:

1. **A feature or fix ships with a test bound to its requirement** (`fp:<slug>`).
2. **The requirements stay true.** If none covers what you're building, propose one.
   If one is wrong or outdated, propose the change — never edit or ignore it.

**Start every task by checking the requirements — before you write code, not
after.** When you pick up a feature or bug, first inventory the full request and
compare it with the active and draft requirements. Find what already covers the work,
what must change, and what is missing. Treating this as the opening move — not a chore
at the end — is what keeps the catalog trustworthy.

### 1. Find and model the requirements — do this first

```bash
fp list                      # active requirements (project comes from .featureparity.yml)
fp list --status draft       # proposed work — check before creating duplicates
fp list --gaps               # the ones with no evidence yet — good places to start
fp show <slug>               # details, acceptance criteria, and existing receipts
fp history <slug>            # why it says what it says, and whether a change is pending
fp changes --source-url URL   # requirement activity prompted by a work item
```

**The requirement catalog is the human-readable product specification, not a box to
tick with one umbrella record.** It records the team's current shared understanding;
it is not a finished decree handed from product to engineering. Refine requirements
through ongoing conversation with customers, domain experts, and builders. The human
product owner decides value and priority; agents should surface gaps, inconsistencies,
alternatives, and useful splits rather than silently making product decisions.

Before coding, enumerate the independently meaningful promises in the request:
user-visible behaviours, policies, limits, plans, deadlines, state transitions,
permissions, failure modes, and affected surfaces. Then model them:

- Give each independently testable or independently failable product promise its own
  focused requirement. If one acceptance sentence joins behaviours that could pass or
  fail separately, split it.
- Use a parent for the broad capability and children for distinct behaviours, policies,
  or surface-specific promises. Do not create requirements for implementation details
  or refactors that make no product promise.
- Put concrete product decisions — prices, quotas, dates, roles, fallbacks — in the
  requirement acceptance criteria. Never leave them only as assumptions in code or a PR.
- Check adjacent requirements and their history. New requirements do not excuse an old
  requirement that the work makes inaccurate; propose a change to keep the whole catalog true.
- Before finishing, reconcile the implementation against the catalog: every shipped
  behaviour maps to a current requirement, every changed promise is recorded, and every
  focused requirement has appropriate marked evidence or an explicit gap. A broad marker
  must never appear to prove several acceptance clauses that its test does not exercise.

**Prevent contradictions before they enter the catalog.** Before proposing a new or changed
promise, compare its intended acceptance criteria with related active and draft requirements
and read their history. Ask whether both promises can be true at the same time for the same
user, state, and conditions. If not, do not add another requirement.

A failing test bound to an existing requirement, or an implementation that only works by
changing one, is a contradiction signal — not permission to weaken the test or write a
second requirement around it. Identify which promise matches product intent, then use
`fp propose-change` (or `--removal`) with the source and reason to put that decision before
a human. If the intent is unclear, stop and ask rather than making the catalog say both things.

**Treat existing tests as protected product evidence.** Before editing an existing test,
determine what expectation it already records and whether CI has passing evidence for it.

- If the test backs passing evidence, do not rewrite it to make the current implementation
  or a new requirement fit. Explicitly flag the intended test edit in the work item and pull
  request. If its expected behaviour would change, propose the requirement change and wait
  for explicit human approval before editing the test; a newly green run must not hide that
  the proof itself changed.
- When FeatureParity reports a changed bound test, run `fp changed-tests` (or add `--json`)
  and compare the accepted and candidate source revisions with the requirement. Record the
  exact candidate through `fp changed-tests assess <id> --candidate-fingerprint <sha256>`
  with a plain-language explanation and one classification: `still_proves`,
  `no_longer_proves`, or `uncertain`. The first resolves only that fingerprint; the others
  remain open for a human product decision. A later fingerprint needs a new assessment.
- A new requirement does not retroactively own or supersede a pre-existing failing test —
  whether the requirement is draft or active. Do not change that test, or adopt it as the new
  requirement's proof, merely to make the new work pass. Surface the conflict and wait for
  explicit human approval to change the existing expectation.

A changed-test finding is an audit signal alongside the testcase's independent CI outcome.
It is not a failed test and is separate from `suspect`, which means requirement wording
changed and its evidence needs re-verification. Neither permits rewriting a test before
product intent is decided.

If no requirement covers what you're building, propose one or a parent/child tree. Agents
always create **drafts**; a human activates them:

```bash
fp propose --slug <slug> --name "..." --required <surface>,<surface> \
  --why "..." --acceptance "..." \
  --source-type fizzy --source-url <card-or-issue-url>
```

**Write a requirement as a product decision someone can approve, not as a design
task.** It should read like a capable teammate wrote it: direct, specific, and free
of boilerplate such as “ensure a seamless experience.”

- **Title:** one clear product promise in present tense, with a concrete subject and
  active verb. Name the user-visible capability, not the work (`“Dispatchers see
  current shipment status”`, not `“Implement status polling”`).
- **Why:** one natural sentence naming who needs this, the problem or risk, and the
  outcome worth protecting. Do not repeat the title, narrate the request or bug
  history, sell the feature, or explain the mechanism.
- **Acceptance:** one independently verifiable rule of observable behaviour that lets a
  reviewer decide whether the promise is true. State the trigger or situation, the result, and material
  boundaries that qualify that same promise. Given/When/Then may clarify those parts,
  but it is not a mandatory template. Split a second result that could fail
  independently into its own requirement instead of comma-chaining it here.
- **Example:** supply one concise concrete case that would pass the general rule, and
  put it after the rule in Acceptance as `Example: ...`. Use the domain's real terms
  and representative data, but ask rather than invent consequential policy. Do not mistake a few examples for the rule
  or let marked tests stand for every case; neither replaces the general rule and
  continued conversation.
- **Numbers and policy:** include a price, limit, timeout, date, role, or fallback only
  when the source made it a real product decision. Never invent a plausible value to
  fill a gap. If the decision matters and the source is silent, ask.
- **Implementation detail:** leave out components, data models, algorithms, endpoints,
  and UI controls unless that interface or constraint is itself part of the promise.

Learn from the request, existing requirements and history, and available evidence about
what users actually do. Look for what they attempt, where they abandon a task, what they
use, and what experiments reveal. Treat the first proposed solution as input, not
unquestionable scope. Preserve important uncertainty as a question rather than
laundering a guess into acceptance criteria.

State the promise itself rather than commentary about it. Avoid openings such as “This
feature…”, “This requirement…”, “The goal is…”, “Users should be able to…”, and “The
system should…”. Use the real actor or product as the subject and an active verb.

- ✅ **Title:** `Dispatchers see current shipment status`
  **Why:** `Dispatchers need to spot delayed shipments before they miss a delivery window.`
  **Acceptance:** `When a shipment's status changes, the dashboard shows the new status; if status is unavailable, it says so instead of presenting stale data as current.`
- ❌ **Title:** `Implement Redis-backed 30-second status polling`
  **Why:** `This important feature ensures a seamless, robust experience.`
  **Acceptance:** `Use a background worker and refresh every 30 seconds.`
  This invents policy, prescribes a design, and never states the product outcome.

Before proposing, answer three questions against the actual fields: Who is this promise
for? How would the concrete example prove it done? Why does the outcome matter? If any
answer is missing or vague, revise the draft or ask the user. Then read it as a manager deciding scope:
is the value clear, can the result be observed, are product decisions
distinguished from guesses, and does every sentence earn its place? If the draft fails
this review, revise it or ask before writing the record.

### 2. If the requirement is wrong, propose a change — don't silently edit it

Shipping something that contradicts a requirement means one of the two is wrong.
Say which, in the record:

```bash
fp propose-change <slug> --why "..." --acceptance "..." \
  --reason "what prompted this" \
  --source-type fizzy --source-url <card-or-issue-url>

fp propose-change <slug> --removal --reason "superseded by <other-slug>"
```

What happens: the change is applied, the requirement drops back to **draft**, and a
human reviews the old-vs-new diff. Rejecting restores the previous wording verbatim.
What it *was* is kept, so nothing is lost either way.

Rules worth knowing before you try:

- Never edit a requirement's wording by any other route. `fp propose-change` is the
  only one that records what it was and what prompted the change.
- You may correct `--name` (the title) or `--slug` through a proposal. Existing evidence
  follows a proposed slug, but every `fp:<slug>` marker still needs the same correction.
  You still cannot remove a required surface.
- You cannot approve or reject — not even your own proposal.
- One open proposal per requirement (409 otherwise). Run `fp history <slug>` first.
- **A requirement awaiting review still counts toward the gate.** Proposing a change
  is not a way to make a red gate green; it only marks the existing evidence
  `suspect`, because the tests were written against wording that has moved.

### 3. Mark the test

Add an `fp:<slug>` comment directly above the test. Keep the test's own name
readable — the marker is the join, not the name.

```ruby
# fp:print_container_qr
it 'prints a QR code onto the container label' do
```

Pin surfaces in the marker when one test satisfies more than one:
`# fp:print_container_qr@api,web`.

Every feature needs one. A requirement with no marked test is a gap, and gaps are
what the gate is eventually going to fail on.

### 4. Report the evidence

```bash
fp report --junit junit.xml --surface <surface> --repo <org/repo> \
  --work-item <card-or-issue-url>
```

Report `present` or `stub` only — **never** claim `passing`/`failing`. Those are CI's
to write, via `fp ci-report`, and the gate trusts them precisely because agents can't
set them.

If you just changed a requirement's wording and re-wrote its tests, re-report the
evidence: that's what clears `suspect`.

### 5. Confirm you didn't break the gate

```bash
fp check                     # exits non-zero if this project now violates its level
```

`fp check --json` if you want to parse the violations. Run `fp help` for the full
command list.
<!-- feature-parity:end -->
