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

- Use scroll-driven pinned scenes for the node canvas: draw connections, send messages along wires, and reveal Debug feedback. Keep marketing copy short.

- Device actions should have visible physical feedback (light glow, dimmer, fan, temperature) synchronized to the scroll timeline. Use native sticky chapters with stable svh heights; avoid ScrollTrigger pin spacers and scroll distances based on changing mobile innerHeight.

- The /gateway subpage is the bilingual installation and pairing guide. Its copyable AI prompt must use public source and selected deployment options, without user-specific hosts or credentials. Keep its steps aligned with gateway/ source, especially Docker vs native environment variables and Home Assistant basic authentication.
- The Home Assistant Apps option uses the repository root `repository.yaml`, the App manifest in `gateway/config.yaml`, and translated Supervisor settings. Keep the website's HA App instructions, GHCR multi-architecture image and pairing configuration aligned with `gateway/DOCS.md`; do not tell users to build on their HA host.
