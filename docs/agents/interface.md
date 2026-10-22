# Interface

- Prefer SwiftUI; use AppKit where needed. Follow macOS interaction and accessibility conventions. A small custom SwiftUI control is appropriate when system controls cannot meet the requirement.
- Render at native resolution. Never scale a system control to enlarge it. Avoid blur, decorative effects, empty padding and dense technical chrome.
- Keep the table focused on useful comparisons. Put counters, rates and explanations in the info panel. Do not freeze today's column layout as a design requirement.
- Write interface text in English; preserve conversation titles. Respect macOS date/time preferences when addressing formatting. The current forced English formatting is a known limitation, not a design principle.
- Labels must explain effects. Distinguish live updates from automatic date selection. Define behavior at midnight, wake and restart.
- Calendar: disable future and empty days. Support a single day and inclusive ranges across empty days; only available endpoints are selectable. Apply commits, Cancel preserves selection. Use calendar-day arithmetic across DST.
- Open supported conversations with `codex://threads/ID`; never link Guardian Reviews. Preserve ID copying even if its table column changes.
- Preserve the pricing retrieval date, `via tools.pwa.ovh` attribution and link to its pricing page.

Verify changed UI in the running app: layout, focus/accessibility, selection, empty/unavailable states and affected date boundaries. Do not claim visual verification from compilation alone. Do not use personal conversation screenshots in public documentation.
