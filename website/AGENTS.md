# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Rivlen prototype decisions

- The selected visual direction is the first warm paper and wine/coral Flow concept, with the final dark Debug chapter blended in for contrast.
- Use simulator or native desktop captures for product imagery. Never use the user's physical iPhone for screenshots.
- Product screenshots should use the portrait iPhone simulator capture inside a generated iPhone shell mockup; do not display the old landscape capture in the marketing page.
- The three download URLs live in src/download-links.js; keep the controls disabled until real Google Play, Pgyer, and iOS URLs are supplied.
