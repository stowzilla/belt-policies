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

## Write, publish, deploy

```bash
belt policies kinds                       # what `belt g policy` can outline
belt g policy cookies                     # → policies/cookie-policy.md (draft)

$EDITOR policies/terms-of-service.md      # write the real text, delete every TODO

belt policies publish terms-of-service    # version = today, drops draft,
                                          # writes db/migrate/<ts>_publish_terms_of_service_<version>.rb
belt deploy dev                           # the migration publishes it to policy_versions
belt policies list                        # version and state of each file
```

`publish` won't publish while the file still has `TODO` placeholders (use
`--force` for a dev-only test). It won't republish text that hasn't changed
either. For a typo fix, use `--minor`: people who accepted an earlier version
aren't asked again.

Never edit a published version in place. The stored text is what people
agreed to. If a file changes without a new version, the publish step leaves
the stored copy alone and says so, and `belt policies list` shows
*edited since published*.

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
| `GET /policies/status` | signed in | `{ policies: [{ …, accepted, pending, accepted_version, accepted_at }], pending: ['terms-of-service'] }` |
| `POST /policies/accept` | signed in | Same as status, after recording |

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

## Ruby API

```ruby
Belt::Policies.current                          # { 'terms-of-service' => PolicyVersion, … }
Belt::Policies.current_version('privacy-policy')
Belt::Policies.pending_for(user_id)             # current versions still to accept
Belt::Policies.accepted?(user_id)               # nothing pending
Belt::Policies.status_for(user_id)              # what GET /policies/status returns
Belt::Policies.accept!(user_id:, policies: ['terms-of-service'], via: 'signup',
                       email:, ip_address:, user_agent:)
Belt::Policies.history_for(user_id)             # every acceptance, newest first
Belt::Policies.account_deleted!(user_id)        # stamp rows for a retention job
```

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
`accepted_at`, `accepted_via`, `ip_address`, `user_agent`, and
`account_deleted_at`. GSIs `UserIndex` (`userId`, `createdAt`) and
`PolicyIndex` (`policy`, `createdAt`). Rows are never edited, apart from the
deletion stamp.

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
