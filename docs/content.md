# Content: how it is written, approved and checked

The public site and the API serve one content file, `content/content.yaml`, validated by
`content/schema/content.schema.json`. The content is public, so it is written under strict
rules and every line is approved by the owner.

## Rules

- The current CV is the source of truth. Skills, dates and employers follow it.
- Never published: phone, email, city, photo, unit numbers, ticket IDs, internal product,
  service and code names, hardware and chip names, internal vendors, and any number that is
  not on the current CV.
- Expired certifications and skills that appear only on older CVs are not republished.
- Case studies are written generically and carry `employer_approval`. It stays `pending`
  until the owner has the employer's go-ahead, and a pending case study is never published.

## Approval

Every line is an object `{text, approved}`. I draft in small batches in chat, the owner
reads the exact wording, and only then is `approved` set to `true`. The published build
(`scripts/check_content.py --build`) contains approved lines only.

## Checks

| Check | Where it runs | What it catches |
|---|---|---|
| Schema | CI and locally | Missing or extra fields, link hosts other than LinkedIn and GitHub, length limits |
| Generic patterns | CI and locally | Ticket IDs, emails, phone numbers, IP addresses, internal host names, URLs outside the allowlist, file paths, account IDs, key material |
| Number allowlist | CI and locally | Any number not listed in `content/allowed-numbers.txt` (all already on the CV) and not a year |
| Private denylist | Locally and in the pre-commit hook | Internal names, vendors, hardware terms and personal details |

All checks read **every** line, approved or not, so a draft never holds a leak. Findings name
the path and the rule, never the matched text or the denylist entry.

### The private denylist

It is a file outside the repository: `~/.portfolio/denylist.txt`, or the path in the
environment variable `CONTENT_DENYLIST`. One term per line (case-insensitive, whole words),
`re:` for a regular expression, `#` for comments. It contains the names the repository must
not contain, so it is **never committed, pasted into chat or copied into any project file**.
CI cannot see it, which is deliberate: CI runs the generic checks and the tests that plant
violations, while the denylist runs on the owner's machine and in the pre-commit hook.
Without the file, the local check refuses to pass.

To add a term, edit the file locally. To rebuild it on a new machine, recreate it from your
own notes.

## Commands

```bash
just content-check          # all checks including the private denylist
just test-app               # linters and tests, including the planted-violation tests
```
