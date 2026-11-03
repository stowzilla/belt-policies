# Changelog

## 0.0.1 (unreleased)

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
