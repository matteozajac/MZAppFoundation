# MZAppFoundation 0.6.2

Screen video recording defaults off when no preference has been saved. Enabling
developer access, launching a Local/Internal build, and opening the console do
not opt a user into capture. The user enables **Record screen video** in Developer
Settings. Explicit saved choices persist; turning it off remains effective after
relaunch. Capture still requires foreground activity and developer access.

The EN/PL setting now clearly identifies screen video and its silent 60-second
buffer. Bug reporting, screenshots, manual voice notes and Pulse logs remain
available with screen video off. Provider SDK pins and deployment targets are
unchanged; setup defaults, samples and compiled metadata select 0.6.2.

Regression tests cover the default with developer access, saved true/false,
and opt-in/revocation across relaunch. Device ReplayKit consent and performance
remain separate physical-device checks.

Validation on 2026-10-10: 37 iOS reporting tests and 64 setup/report tooling
tests passed locally. No app archive or TestFlight upload was performed.
