# belt-policies

Versioned policies for [Belt](https://belt.dev) apps: Terms of Service,
Privacy Policy, Cookie Policy, and whatever else you publish. Plus the record
of **who agreed to which version, when, how, and from where**.

> [!IMPORTANT]
> **This is not legal advice.** belt-policies is plumbing. It generates
> *outlines* (headings, plus TODO prompts for what usually goes under them) and
> records acceptances. It does not write your policies and cannot tell you
> what they must say for your business or jurisdiction. Nothing in this gem was
> written or reviewed by a lawyer. Have a qualified attorney write or review
> your policies before you rely on them.

## What you get

- `belt g policies` installs two models, a controller, four routes, and the
  DynamoDB tables (through `belt setup tables`)
- `belt g policy <kind>` outlines a policy as a **draft** markdown file in
  `policies/`
- `belt policies publish <slug>` gives it a new version and writes a data
  migration. `belt deploy` runs the migration, which copies the exact text into
  `policy_versions`
- An API your frontend calls to show the current policies, check what the
  signed-in user still has to accept, and record their acceptance
- A `before_action` that holds signed-in users until they've accepted the
  current versions

## Install

```ruby
# Gemfile
gem 'belt-policies'
```

```bash
bundle install
belt g policies --with terms-of-service,privacy-policy
```

```
  create  lambda/models/policy_version.rb
  create  lambda/models/policy_acceptance.rb
  create  lambda/controllers/api/policies_controller.rb
  create  policies/README.md
  update  config/routes.rb (policy routes in gateway :api)
  update  infrastructure/modules/app/dynamodb.tf
  create  policies/terms-of-service.md (draft)
  create  policies/privacy-policy.md (draft)
```

Options: `--gateway NAME` (default: the first gateway in `config/routes.rb`),
`--auth NAME` (default: `cognito`), `--skip-routes`, `--force`.

### Apps without a gateway authorizer

The controller reads the user from the gateway authorizer's claims. If your
app authenticates in the Lambda instead (no authorizer on the gateway), use
`--auth none`. The routes get `auth: :none`, and the generated controller has
a `policies_user_id` for you to fill in. Until you do, it raises instead of
quietly answering 401:

```ruby
module ApiControllers
  class PoliciesController < ApplicationController
    include Belt::Policies::Controller

    private

    def policies_user_id
      signed_in_user&.id          # however your app knows who is signed in
    end

    def policies_user_email
      signed_in_user&.email
    end
  end
end
```

## Write, publish, deploy

```bash
belt policies kinds                       # what `belt g policy` can outline
belt g policy cookies                     # → policies/cookie-policy.md (draft)

$EDITOR policies/terms-of-service.md      # write the real text, delete every TODO

belt policies publish terms-of-service    # version = today, drops draft,
                                          # writes db/migrate/<ts>_publish_terms_of_service_<version>.rb
belt deploy dev                           # the migration publishes it to policy_versions
belt policies list                        # version and state of each file
belt policies check                       # CI: fail if published text was edited
```

`publish` won't publish while the file still has `TODO` placeholders (use
`--force` for a dev-only test). It won't republish text that hasn't changed
either. For a typo fix, use `--minor`: people who accepted an earlier version
aren't asked again.

Never edit a published version in place. The stored text is what people
agreed to. If a file changes without a new version, the publish step leaves
the stored copy alone and says so, and `belt policies list` shows
*edited since published*. Add `belt policies check` to CI to catch it
before deploy: it exits non-zero, naming the file, when a published policy's
text no longer matches the version it was published as. It reads the files
only, so CI needs no AWS access.

### Text built into the site

`GET /policies/{slug}` serves the published text, but a static page can build
it in instead. With Vite, import the files and strip the front matter:

```js
// src/policies.js
const files = import.meta.glob('../policies/*.md', { query: '?raw', import: 'default', eager: true })

export const policies = Object.fromEntries(
  Object.entries(files).filter(([path]) => !path.endsWith('/README.md')).map(([path, source]) => [
    path.match(/([^/]+)\.md$/)[1],                            // slug
    source.replace(/^---\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|$)/, ''), // body only
  ])
)
```

The built page shows whatever is in the file, so keep `belt policies check` in
CI: it fails when the file was edited without a new version. When you record
an acceptance, send the `version` from the file's front matter. If it isn't
the published one, `accept` answers 409.

### Policy files

```markdown
---
title: Terms of Service
version: '2026-11-02'
effective_date: '2026-11-02'
requires_acceptance: true      # false: published only (cookie policy, accessibility)
requires_reacceptance: true    # false: a minor edit; earlier acceptances still count
draft: true                    # removed by `belt policies publish`
---
# Terms of Service
…
```

Built-in kinds: `terms-of-service`, `privacy-policy`, `cookie-policy`,
`acceptable-use-policy`, `community-guidelines`, `refund-policy`, `eula`,
`seller-agreement`, `data-processing-agreement`, `sms-terms`,
`accessibility-statement`, `do-not-sell`. Aliases work (`tos`, `privacy`,
`cookies`, `aup`, `dpa`, …). Any other slug gets a blank outline:
`belt g policy beta-terms --title "Beta Program Terms"`.

## API

| Route | Auth | Returns |
|-------|------|---------|
| `GET /policies` | none | `{ policies: [{ policy, version, title, effective_date, requires_acceptance, … }] }` |
| `GET /policies/{slug}` | none | `{ policy: { …, content, current } }`. Add `?version=` for an older version |
| `GET /policies/status` | signed in | `{ policies: [{ …, accepted, pending, accepted_version, accepted_at }], pending: ['terms-of-service'] }`. Add `?subject_id=` for a subject |
| `POST /policies/accept` | signed in | Same as status, after recording. Optional `subject_id` and `metadata` |

```js
// Sign-up form: the box is ticked, so record what the person was shown.
await api.post('/policies/accept', {
  policies: shown.map(p => ({ policy: p.policy, version: p.version })),
  via: 'signup',
})
```

Send the version you displayed. If a newer version was published in the
meantime, the API answers **409** with `details.current_version`, records
nothing, and you show the new text. Accepting a version again records nothing
new. Email comes from the token's claims. IP address and user agent come from
the request.

To refuse an acceptance, override `policies_may_accept?` in your controller.
It gets the `subject_id` (or nil), and returning false answers **403**
`acceptance_not_allowed`, recording nothing. Use it to turn away a token that
may not agree to anything (a child's profile) or a subject the user doesn't
own:

```ruby
def policies_may_accept?(subject_id)
  return false if child_profile_token?
  subject_id.nil? || current_parent.child_ids.include?(subject_id)
end
```

### Acceptances about a subject

Some acceptances are about someone else: a parent consenting for each child
under the same notice. Pass `subject_id`:

```js
await api.post('/policies/accept', {
  policies: [{ policy: 'parental-notice', version: notice.version }],
  subject_id: child.id,
  metadata: { terms_version: terms.version },   // optional, kept on the row
  via: 'add-child',
})
```

Each user, subject, and policy version gets its own row, so consent for a
second child under the same version is recorded too. Acceptances about a
subject never count toward the user's own policies. `GET /policies/status`
answers for the user, and `GET /policies/status?subject_id=child-abc` answers
"has this child's consent been given under the current notice?"

### Hold users until they accept

```ruby
module ApiControllers
  class ApplicationController < BeltController::Base
    include Belt::Policies::RequireAcceptance
    before_action :require_current_policies!
  end
end
```

A signed-in user with pending policies gets **403**
`{ error, details: { code: 'policies_pending', pending: [...] } }`. The
policies routes themselves stay open. Routes behind the guard need
`tables: %i[policy_versions policy_acceptances]` so the Lambda can read them.

Limit it with `only:` / `except:`, or `skip_before_action` in one controller:

```ruby
before_action :require_current_policies!, except: %i[show play]
```

#### When not to use the guard

The guard blocks **every** guarded route the moment a new version is
published. Don't use it where that would strand someone mid-task: a game
people play without signing in (a signed-in player would be locked out of
their own table), a checkout, an upload. Prompt instead.

#### Prompt, don't block

Leave the guard off and let the client ask:

1. After sign-in, and when the app comes back to the foreground, call
   `GET /policies/status`.
2. If `pending` isn't empty, fetch each pending policy
   (`GET /policies/{slug}`), show it, and `POST /policies/accept` with the
   versions shown.
3. Gate only what must wait (account changes, purchases) with
   `before_action :require_current_policies!, only: %i[…]`, or check
   `Belt::Policies.accepted?(user_id)` in that action.

## Ruby API

```ruby
Belt::Policies.current                          # { 'terms-of-service' => PolicyVersion, … }
Belt::Policies.current_version('privacy-policy')
Belt::Policies.pending_for(user_id)             # current versions still to accept
Belt::Policies.accepted?(user_id)               # nothing pending
Belt::Policies.status_for(user_id)              # what GET /policies/status returns
Belt::Policies.accept!(user_id:, policies: ['terms-of-service'], via: 'signup',
                       email:, ip_address:, user_agent:,
                       subject_id: nil, metadata: nil)  # optional
Belt::Policies.history_for(user_id)             # every acceptance, newest first
Belt::Policies.history_for(user_id, subject_id: 'child-abc')
Belt::Policies.account_deleted!(user_id)        # stamp rows for a retention job
Belt::Policies.expire_deleted!(older_than: 3 * 365 * 86_400)  # delete stamped rows; returns a count
Belt::Policies.import_acceptance!(user_id:, policy:, version:, accepted_at:)  # pre-gem acceptances
```

`status_for`, `pending_for`, and `accepted?` take `subject_id:` too.

### Retention

`account_deleted!` stamps a deleted account's rows with `account_deleted_at`
and keeps them. `expire_deleted!` deletes rows stamped before the cutoff.
`older_than:` is seconds (or an `ActiveSupport::Duration`) or a `Time`. It
scans the table a page at a time and returns how many rows it deleted, so a
daily scheduled job can call it:

```ruby
# lambda/jobs/expire_policy_acceptances.rb, run daily
Belt::Policies.expire_deleted!(older_than: 3 * 365 * 86_400)   # kept 3 years after deletion
```

The job's Lambda needs the `policy_acceptances` table. How long to keep the
rows is your call (and your lawyer's), not the gem's.

### Importing acceptances from before the gem

If your app already recorded acceptances, copy them in with a data migration.
`import_acceptance!` keeps the original `accepted_at`, records against the
version you name even if it was never published (with no `content_sha256`,
since the text wasn't stored), and records nothing on a re-run:

```ruby
# db/migrate/20261105000000_import_terms_acceptances.rb
TermsAcceptance.all.each do |old|
  Belt::Policies.import_acceptance!(
    user_id: old.user_id, policy: 'terms-of-service', version: old.terms_version,
    accepted_at: old.accepted_at, via: 'import', metadata: { 'source' => 'terms_acceptances' }
  )
end
```

It takes the same `email:`, `ip_address:`, `user_agent:`, `subject_id:`, and
`content_sha256:` as an acceptance. To have imported rows count toward the
current version, publish that version under the same version string
(`belt policies publish terms-of-service --version 2025-06-01`). Otherwise
people are asked to accept the newly published version.

```ruby
Belt::Policies.configure do |c|
  c.cache_ttl = 60                   # seconds a Lambda caches current versions
  c.policies_dir = 'policies'        # where the markdown lives
  c.version_model = 'PolicyVersion'
  c.acceptance_model = 'PolicyAcceptance'
end
```

## Tables

**`policy_versions`**: one row per published version, keyed
`<policy>@<version>`. Holds `title`, `effective_date`, `published_at`,
`requires_acceptance`, `requires_reacceptance`, the full `content`, and its
`content_sha256`. GSI `PolicyIndex` (`policy`, `publishedAt`).

**`policy_acceptances`**: one row each time someone agreed. Holds
`user_id`, `email`, `policy`, `version`, `policy_version_id`, `content_sha256`,
`accepted_at`, `accepted_via`, `ip_address`, `user_agent`, `subject_id`,
`metadata` (a map), and `account_deleted_at`. GSIs `UserIndex` (`userId`,
`createdAt`) and `PolicyIndex` (`policy`, `createdAt`). Rows are never edited,
apart from the deletion stamp, and are deleted only by `expire_deleted!`.

The models live in your app (`lambda/models/`), so `belt setup tables` can see
them and you can add to them.

## Remove

```bash
belt d policies      # models, controller, routes; keeps policies/*.md and db/migrate
belt d policy cookie-policy
```

Removing the models drops both tables on the next deploy, unless deletion
protection is on.

## License

MIT
