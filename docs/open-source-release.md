# Open-source publication checklist

Preparation does not change GitHub visibility or submit an OpenAI application.
Read the [audit](open-source-audit.md) before publishing the repository's history.

## Review and validate the proposed release

- Review the README, MIT license, dependency notices, contributing guide, security
  policy, and code of conduct. Original code and original Inbox artwork use MIT;
  vendor SDKs and platform services keep their own terms.
- Include the intended Inbox source/tooling files in the release; they started as
  untracked work. Keep recordings, user reports, personal routes, credentials,
  generated builds, and local agent output out of Git and release assets.
- Run `python3 scripts/scan_secrets.py --history` with Gitleaks installed. It scans
  tracked files, non-ignored untracked files, and all locally available refs. Use
  a fresh full clone to repeat the history scan immediately before publication.
  A scan cannot establish that every possible secret or private datum is absent.
- Run the checks in [CONTRIBUTING.md](../CONTRIBUTING.md). Local checks do not prove
  GitHub Actions, physical-device behavior, live provider delivery, or purchases.
- Review all public release artifacts separately. A clean source scan does not
  cover uploaded ZIPs, screenshots, binaries, reports, or their metadata.
- Keep existing release tags intact. A newly licensed release should contain the
  license and notices itself; older source archives do not gain those files.

## Configure GitHub at publication

These are repository-owner operations to perform when ready to expose the code:

1. Commit and push the reviewed preparation, verify the final branch and remote
   state, and wait for passing public CI. Avoid publishing a partial file set.
   Use ordinary branch/tag pushes; do not mirror-push private local checkpoint refs.
2. Review GitHub's visibility-change notice and make the repository public.
   Historical commits, author metadata, tags, issues, and releases may become
   visible. If a real secret is ever found, revoke it before any history cleanup;
   deleting it from the latest commit is insufficient.
3. Enable private vulnerability reporting and verify the **Report a vulnerability**
   action. Enable secret scanning, push protection, dependency graph, and Dependabot
   alerts where available. Settings are not enabled by adding policy files.
4. Protect `main` against force-pushes and deletion; require passing Validate and
   Security checks for pull requests. Choose review requirements that still allow
   a sole maintainer to ship fixes, and review GitHub Actions fork-run permissions.
5. Add a concise repository description and topics such as `swift`, `swift-package`,
   `swiftui`, `ios`, `visionos`, `macos`, `logging`, and `developer-tools`.
6. Publish a new version only after updating authoritative version stamps and
   validating dependency pins. Include the license, notices, changes, supported
   toolchain, and validation boundaries in release notes. Do not overwrite tags.

Issue forms and the pull-request template are provided. No sponsor account, CLA,
paid support commitment, or automatic AI issue-processing service is implied.

## Maintainer program

Use the [Codex for Open Source application notes](codex-for-open-source.md) after
public access and maintenance evidence can be verified. Keep account-specific
application details outside the repository.
