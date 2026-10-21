# Open-source preparation audit

Date: 2026-10-21. Repository: `matteozajac/MZAppFoundation`.

## Outcome

No credential matches were detected by Gitleaks in the proposed publishable files,
the locally available Git history, or a fresh mirror of the GitHub repository.
This is a scoped audit, not a guarantee that all secrets or private data are absent.

Documentation, licensing, community files, original Inbox artwork, HTTPS setup
URLs, and ongoing security checks were prepared locally during this audit.
Visibility and security settings were unchanged at that preparation snapshot.
The subsequent publication requires separate GitHub readback; it is not implied
by these source checks. The OpenAI application has not been submitted.

The reporting implementation originated in JoinOurDay. On 2026-10-21, maintainer
Mateusz Zając confirmed that he has the required rights for this open-source
release, resolving the previously noted publication blocker. This audit records
that confirmation; see [source provenance](../THIRD_PARTY_NOTICES.md#reporting-source-provenance).

## Scope and evidence

- The checkout initially reported 0.5.1 at `0326b4a`, with a modified README and
  untracked MZ Inbox tooling. That existing work was included in the review.
- GitHub's current `main` was read back at
  `0594bf52cf518b777194cc03fed43f98bdabe756`, tagged 0.6.2. The local preparation
  is brought forward to that existing revision while preserving the Inbox work.
- A fresh remote mirror contained one branch, nine tags, and 12 reachable
  commits. Gitleaks 8.30.1 with full-history/all-ref coverage found zero matches.
- The independent local audit pinned 39 refs covering 38 reachable commits,
  including local T3 checkpoints in addition to branches/tags. It found zero
  Gitleaks matches, including in 12 unreachable blobs. Those local checkpoint refs
  are not advertised by the remote. The final proposed tree scan covered 223 files
  and also reported zero matches.
- Publication-candidate scans include tracked files and non-ignored untracked
  files. The reusable scanner deliberately includes tracked files even if they
  match `.gitignore`, and checks historical deleted content with `--history`.
- Manual review covered provider configuration, credential-like filenames,
  account-specific guidance, absolute paths, source/examples, SDK dependencies,
  and the existing Inbox binary artwork and generator.
- Five existing GitHub releases had no uploaded assets; release descriptions
  produced zero Gitleaks matches. The Actions artifacts API reported zero stored
  artifacts at the time of review. Hosted job logs, private provider consoles,
  other repositories, and future uploads are outside this audit.

## Findings and changes

### Credentials and provider configuration

No actual administrative key, OAuth token, password, signing key, or service-account
credential was identified in the audited publication candidates/history. Synthetic
credentials and private-looking strings in redaction tests are fixtures, not live
access evidence. No credential rotation was performed.

Personal account defaults and machine-specific skill paths were replaced with
owner-resolved guidance and portable repository paths. Examples use synthetic app
identifiers, empty provider configuration, and disabled delivery. Host-owned
configuration, provider files, signing material, and common report/media output
are excluded by ignore rules. An ignore rule never removes already tracked files.

### Metadata and local evidence

Git author and annotated-tag metadata include the maintainer's name and personal
email. The verified public support email is also used by the security/conduct
policies. Public Git history exposes that metadata. It is personal information,
not an authentication secret; existing commit and tag identities were retained.
Historical documentation may also name earlier app integrations. Current public
guides were generalized; existing tags were not rewritten.

Ignored `output/` contains local bug-report archives, recordings, logs, screenshots,
and agent evidence. These remain local and must not be attached to a release or
uploaded as a whole-workspace archive. Private report/session identifiers were
removed from the public Inbox validation narrative. Publish only intended source
files and separately audited release assets.

### Artwork and third-party rights

The unfinished Inbox tool originally rendered a private Apple/Shortcuts glyph into
bundled icon files without a recorded redistribution grant. The generator and
all three icon files were replaced with original geometric artwork under MIT.
The generator no longer loads or extracts system artwork. Older copies remain
only in private local T3 checkpoint history and must not be mirror-pushed. The companion keeps
the resource filenames required by its existing packaging.

The MIT license applies to original project material. Vendor SDKs, their binary
components, development tools, and optional transcription tools retain their own
terms. The complete resolved inventory and binary-component cautions belong in
the notices. Reporting-source rights are recorded as confirmed by the maintainer above.

### Contributor and automation readiness

Public README/integration/migration/verification guides, contributor and conduct
policies, a security policy, CODEOWNERS, issue forms, a PR template, and a changelog
are supplied. New and updated generated integrations use HTTPS package URLs and
recognize existing SSH references without creating duplicate package references.

CI has read-only default permissions, checkout credentials disabled, SHA-pinned
third-party actions, a checksum-pinned Gitleaks download, full-history secret
checks, dependency review, and weekly dependency-update configuration. Real scanner
fixtures verify redaction, untracked-file handling, tracked ignored files, and
secrets removed from the current tree. Remote CI execution and GitHub security
settings require separate live readback after publishing the prepared changes.

## Validation

After reconciling with 0.6.2:

- 54 SDK-free core/UI Swift tests passed through MobileBuildMCP.
- 71 Python tooling tests passed, including real Gitleaks scanner integration
  fixtures and native/XcodeGen setup/legacy-SSH-to-HTTPS migration checks.
- 34 Inbox receiver tests passed; the dependency-free macOS Inbox Release build
  passed through MobileBuildMCP. Original artwork regenerated successfully.
- The README's separate core executable printed `Tracked calls: 1`.
- Workflow lint (`actionlint`), Markdown local-link/JSON/YAML checks, and
  `git diff --check` passed. Remote GitHub Actions for the preparation had not
  run at this local validation snapshot.

The existing dependency-version checker reported newer Sentry/RevenueCat versions
available. No SDK upgrade was included in publication preparation; the existing
0.6.2 pins and compatibility exceptions were preserved. That checker is a release
availability report, not a vulnerability scan.

Full iOS/visionOS sample builds, live provider delivery, symbolication, purchases,
physical-device recording/consent, notarization, and public binary distribution
were not revalidated in this task. Historical release checks remain dated evidence.

## Publication and application

Complete [the publication checklist](open-source-release.md), including the final
full-clone scan, GitHub security settings, and a newly licensed release. Do not use `git push --mirror`: normal branch/tag publication must not
export private local checkpoint refs.

The [OpenAI application notes](codex-for-open-source.md) contain official links and
an evidence-based draft. The repository was private with zero stars and forks at
the time of review; no public adoption claims or benefit approval are inferred.
