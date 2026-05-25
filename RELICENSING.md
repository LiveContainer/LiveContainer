# Relicensing Record

LiveContainer was originally licensed under Apache License 2.0, then
relicensed to AGPL-3.0-only following integration of AGPL-3.0
components from SideStore.

This document records the consent of each copyright holder to the
addition of a second licensing option:

> GNU Lesser General Public License version 3 or later, with the
> Linking Exception set forth in the `LICENSE` file at the root of
> this repository.

Distribution of LiveContainer under either AGPL-3.0-or-later or
LGPL-3.0-or-later-with-Linking-Exception is at the recipient's option,
as described in `LICENSE`.

## Contributor Consents

The following contributors have agreed to license their contributions
under both AGPL-3.0-or-later **and** LGPL-3.0-or-later WITH the Linking
Exception defined in `LICENSE`:

<!--
Format: one row per contributor. Add a row only after receiving an
explicit written consent (email, signed PR comment, or signed
statement). Link to the consent record where possible.

| GitHub handle | Name | Date | Consent record |
|---------------|------|------|----------------|
| @example      | Example Person | 2026-MM-DD | https://github.com/LiveContainer/LiveContainer/issues/NNNN |
-->

| GitHub handle | Name | Date | Consent record |
|---------------|------|------|----------------|
|               |      |      |                |

## Process

1. A contributor signals consent by commenting on the relicensing
   tracking issue with the phrase:

   > "I, <full name>, the copyright holder of my contributions to
   > LiveContainer (as identified by GitHub handle @<handle>),
   > agree to additionally license those contributions under
   > LGPL-3.0-or-later WITH the Linking Exception set forth in the
   > LICENSE file of the LiveContainer repository, in addition to
   > the existing AGPL-3.0-or-later license."

2. A maintainer verifies the GitHub identity, dates the entry, and
   adds a row to the table above with a link to the comment.

3. If a contributor declines or does not respond, the maintainer
   either:
   - Reverts or rewrites the contribution to remove their copyright,
     and notes the affected commits in this file; or
   - Excludes the contribution from any LGPL-licensed distribution
     (the code remains in the repository under AGPL-3.0 only).

## Outstanding Contributions

<!--
List any contributions whose copyright holders have not yet consented.
These remain licensed under AGPL-3.0 only.

- Commits by @handle (issue #N): pending response since 2026-MM-DD.
-->

(none recorded yet)

## Third-Party Code Consents

ZSign (`ZSign/`) is included in the DUAL-LICENSED COMPONENTS scope of
`LICENSE`, but contains code inherited from third-party upstreams. To
fully validate the dual-license offer for ZSign, the following
external consents are needed:

| Upstream | Original License | Consent needed? | Status |
|----------|------------------|-----------------|--------|
| [zhlynn/zsign](https://github.com/zhlynn/zsign) | MIT | No (MIT permits sublicensing) | N/A |
| [khcrysalis/Feather](https://github.com/khcrysalis/Feather) (modifications to ZSign carried into LiveContainer) | GPL-3.0 | **Yes** | Pending |

Until the khcrysalis consent is recorded, downstream users relying on
option (B) for ZSign should refer to the cure-period clause in the
"ZSIGN PROVENANCE" section of `LICENSE`.

## Past Relicensing Events

- **2024**: Apache-2.0 → AGPL-3.0-only (driven by integration of
  AGPL-3.0 components from SideStore).
- **2026**: AGPL-3.0-only → AGPL-3.0-or-later OR LGPL-3.0-or-later
  WITH Linking Exception (this change).
