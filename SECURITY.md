# Security policy

## Reporting a vulnerability

Use GitHub's [private vulnerability reporting form](https://github.com/matteozajac/MZAppFoundation/security/advisories/new) when it is available for this repository. If the form is unavailable, email maintainer Mateusz Zając at [matteo.zajac@gmail.com](mailto:matteo.zajac@gmail.com) with the subject `MZAppFoundation security report`. This contact is independently published on [the maintainer's website](https://matteozajac.com/projects/masseter.html#support).

Private vulnerability reporting depends on the repository's GitHub settings. This policy does not assert that it is enabled; GitHub explains the distinction in its [private reporting documentation](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/report-privately).

Do not disclose a vulnerability in a public issue, pull request, or discussion. Do not send passwords, API tokens, private keys, customer data, real purchase receipts, or unredacted bug-report archives through any reporting channel. Use synthetic data and the smallest reproduction that demonstrates the problem. If sensitive evidence is essential, describe what it contains first so a suitable transfer can be arranged.

Useful report details include:

- Affected version or commit, package product or tool, platform, and OS version.
- Reproduction steps or a small synthetic proof of concept.
- Expected behavior, observed behavior, and the security or privacy impact.
- Any prerequisites, such as a particular provider adapter or local configuration.

If a credential has been exposed, revoke or rotate it with its provider; do not include its value in the report. Problems in an upstream SDK or hosted service should also be reported to that provider through its own security channel when appropriate.

## Maintenance scope

Security maintenance is limited to the current `main` branch, with no backport commitment for older tags. Include your installed version when reporting a problem, even if you cannot reproduce it on `main`.

The maintainer will assess the report and coordinate a fix and disclosure as appropriate. Please allow a fix to be prepared before publishing exploit details. Response times depend on maintainer availability.
