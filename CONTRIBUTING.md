# Contributing to Nuvio HTPC

This is an independent desktop fork. Read the [README](README.md),
[development guide](Docs/Development.md) and [testing guide](Docs/Testing.md) before
changing platform behavior or packaging.

Keep a change focused on its stated problem. For fixes, describe a concrete trigger,
the previous behavior and the resulting behavior. User/maintainer authorization
can define a broader scope, but do not bundle unrelated product or architecture
changes into a small fix.

## Implementation and verification

- Preserve platform-specific behavior: Windows native-image metadata is not the
  macOS runtime, and Windows APIs should stay behind the appropriate OS boundary.
- Check the actual source/build task before documenting a capability or command.
- Run tests relevant to the change. Explain platform/hardware limitations and keep
  manual or provider-specific results distinct from automated tests.
- Test macOS consent from a packaged app; a Terminal-launched test does not prove
  the Finder privacy flow. Never change a tester's privacy/firewall settings just
  to obtain a passing result.
- Keep credentials, private configuration and generated build/test output out of commits.

For documentation-only changes, validate relative links, examples, task/source
references and consistency. A full application rebuild is not needed unless an
implementation change is also made. Preserve historical release notes and identify
reference copies as upstream material instead of rewriting their protocol claims.

## Pull requests

Use the [pull-request template](.github/PULL_REQUEST_TEMPLATE.md). Explain the
problem, final scope, validation and material limitations; include relevant visual
evidence for UI changes. Link the issue or authorization where applicable, and
explain when a documentation/maintenance change has no linked issue.

Update the affected guides and the Unreleased section of [CHANGELOG.md](CHANGELOG.md)
for user-visible changes. Do not bump the release version or publish artifacts as
part of a documentation update unless that action is explicitly requested.
