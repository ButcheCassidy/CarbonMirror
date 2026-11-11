# CarbonMirror — project rules

Android → Mac screen mirroring, full duplex. Layout: `android/` (Gradle, Kotlin), `macos/` (Xcode, Swift).

## Git identity (mandatory)
Before any commit, run:
```bash
git config user.name "ButcheCassidy"
git config user.email "354005634+ButcheCassidy@users.noreply.github.com"
```
- All commits and tags are authored as ButcheCassidy with the GitHub noreply email.
- No `Co-Authored-By` or other AI attribution trailers in commit messages.
- No "Generated with Claude Code" lines, session IDs or claude.ai session links in commits, code, docs, PR titles/bodies or comments.

## Workflow
- All work is committed and pushed directly to `main`. No feature branches, no PRs.
- Before committing: `git pull --ff-only origin main`; run the relevant build/tests; never force-push `main`.
- Releases: see `docs/RELEASING.md` (tag `vX.Y.Z` or run the Release workflow).

## Security / encryption
- Never commit secrets, keystores, `.p12`, `.env`, `local.properties`. Secrets live in GitHub Environment `release`.
- Mirroring/control channels must be encrypted and authenticated (e.g. TLS 1.3 / DTLS or Noise with pinned keys from a pairing step). No plaintext transport, including on LAN.
- Use platform keystores (Android Keystore, macOS Keychain) for long-term keys.
- Responses: structured, concise, no filler.

## Resume (project memory)
- Build in progress. Read `HANDOFF.md` first and continue from its **Next steps**; the user supplies the full spec prompt (`CarbonMirror_Build_Prompt.md`) and the app logo.
- Build only; fix bugs only when strictly necessary to continue. Test UI at every stage: elements exactly where the spec puts them, no overflow at any size.
- Liquid Glass only for Settings and not-connected screens; mirroring UI fully opaque.
