# Changelog

## 0.0.2

- Acceptances about a subject: `accept!(subject_id:, metadata:)` records one
  row per user, subject, and policy version, so a parent's consent for a
  second child under the same notice is kept. `history_for`, `status_for`,
  `pending_for`, and `accepted?` take `subject_id:`. Without it they look at
  the user's own acceptances only. `POST /policies/accept` takes
  `subject_id` and `metadata`, and `GET /policies/status` takes `?subject_id=`.
  New `subject_id` and `metadata` attributes on `PolicyAcceptance`
- `Belt::Policies.expire_deleted!(older_than:)` deletes acceptance rows whose
  account was deleted before the cutoff, a scan page at a time, and returns
  the count
- `Belt::Policies.import_acceptance!` records an acceptance made before the
  app used this gem: original date, no stored text, safe to re-run
- `belt policies check` exits non-zero when a published policy's text was
  edited without a new version
- `belt g policies --auth none` writes `auth: :none` routes and a controller
  that asks the app for the user instead of reading gateway claims
- Controllers can override `policies_may_accept?(subject_id)` to refuse an
  acceptance (403 `acceptance_not_allowed`)
- README: when not to use the `RequireAcceptance` guard, prompting instead of
  blocking, and building policy text into a Vite site

## 0.0.1

First release.

- `belt g policies` installs `PolicyVersion` / `PolicyAcceptance` models (and so
  the `policy_versions` / `policy_acceptances` tables), a policies controller,
  and routes: `GET /policies`, `GET /policies/{slug}`, `GET /policies/status`,
  `POST /policies/accept`
- `belt g policy <kind>` outlines a policy as a draft in `policies/<slug>.md`.
  There are 12 built-in kinds, and any other slug gets a blank outline.
  Outlines only, not legal advice
- `belt policies list | kinds | publish`. `publish` versions a policy, clears
  draft, and writes the data migration that publishes it on `belt deploy`
- `Belt::Policies.accept!`, `status_for`, `pending_for`, `accepted?`,
  `history_for`, `account_deleted!`
- `Belt::Policies::RequireAcceptance` before_action guard
