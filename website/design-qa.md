# Rivlen marketing site design QA

## Comparison target

- Source visual truth: `/Users/hina/.codex/generated_images/01a15edc-421a-7733-84b8-ba278f96934b/exec-cfce49a6-356a-42d2-b84c-7939b350fcf5.png` (1536 × 1024 px, generated warm paper / wine / coral Flow direction selected by the user).
- Implementation: `http://127.0.0.1:4173/` served from `website/` by Vite.
- Implementation screenshot path: browser-rendered CUA capture of the implementation URL (the browser screenshot API exposed the capture in the QA session but did not provide a filesystem path). Desktop and mobile captures were both reviewed.
- Desktop viewport: 1251 × 721 CSS px, device pixel ratio 1; scroll-driven pinned node, form, and Debug scenes inspected at multiple scroll positions.
- Mobile viewport: 390 × 844 CSS px, device pixel ratio 1.
- State: Chinese light mode for the primary comparison; English toggle and dark mode were also checked.

## Evidence

- Full-view desktop capture: hero composition, marquee, complex Flow story, native Home Assistant form, dark Debug chapter, private Gateway chapter, and download section were inspected while scrolling through the local page.
- Focused hero comparison: the implementation keeps the source's warm paper field, wine/coral ribbon, phone canvas, soft shadows, and spacious editorial hierarchy. The generated hero is used as a real cropped asset at `public/assets/flow-hero.png`; live HTML copy replaces the source's English headline so the page can switch between Chinese and English.
- Focused product evidence: `public/app-shots/rivlen-iphone17pro.png` is a portrait iPhone 17 Pro simulator capture, and `public/assets/rivlen-iphone-mockup.png` is its generated front-facing shell mockup. No physical iPhone was used. The Node-RED node rail, Home Assistant form, Debug console, gateway rings, and download controls were inspected at both desktop and 390 px layouts.
- Primary interactions checked: nav anchors, CTA scroll, light/dark toggle, Chinese/English toggle, responsive stacking, disabled download states, and mobile language button accessibility label.
- Console evidence: a fresh browser tab at the implementation URL reported no warning or error logs after load.

## Scroll animation pass

- Node canvas stays pinned while three SVG wires draw progressively. A message travels across each wire, the receiving node glows, and Debug reveals a notification dot and payload result.
- Home Assistant form stays pinned while fields enter in order; Debug messages enter individually in a second pinned scene. Gateway rings and devices assemble with scroll progress.
- Inspected desktop and 390 × 844 layouts at the connection, message, completion, form, and Debug stages. Mobile return-wire bends stay inside the viewport, and pinned shells retain their horizontal padding.
- Timelines use scrub so scrolling upward reverses the sequence. Reduced-motion preference renders static content without pinning.
- Browser console: no errors or warnings during the scroll pass.

## Findings

No actionable P0, P1, or P2 differences remain.

- P3 acceptable adaptation: the source is a single English visual and the implementation uses live bilingual HTML copy, so line breaks, wording, and text density vary by language. The visual hierarchy and selected art direction remain aligned.
- P3 follow-up: replace the disabled download states after the real Google Play, Pgyer, and iOS URLs are supplied in `src/download-links.js`.

## Comparison history

1. Initial desktop pass: the fixed navigation used blend behavior and became hard to read over the dark Debug chapter. Severity P2.
2. Fix: removed blend behavior and added explicit translucent light and dark navigation surfaces with borders.
3. Post-fix pass: desktop and mobile captures show readable navigation in both themes; no P0/P1/P2 findings remain.
4. Initial mobile pass: the compact language control had no accessible name because its visible label is hidden at the small breakpoint. Severity P2.
5. Fix: added a localized `aria-label` to the language toggle.
6. Post-fix pass: the mobile accessibility tree exposes `English` / `中文`, and the toggle changes the page title and copy correctly.
7. Initial product image pass: the displayed simulator capture was landscape and made the phone proportions read incorrectly on the page. Severity P2.
8. Fix: captured the running app in the iPhone 17 Pro simulator, generated a transparent iPhone shell around the portrait capture, and replaced the displayed asset with the portrait mockup. Added an explicit Node-RED node showcase and shortened the supporting copy to design concepts.
9. Post-fix pass: the page uses the portrait shell mockup at desktop and mobile widths; no P0/P1/P2 findings remain.

## Implementation checklist

- [x] Warm paper, wine, coral, and soft-shadow visual tokens map to the selected direction.
- [x] GSAP entrance, parallax, reveal, progress-line, and Debug pulse interactions are responsive and reduced-motion aware.
- [x] Desktop pinned storytelling layout collapses into a readable mobile stack.
- [x] Portrait simulator product capture and generated iPhone shell artwork are real image assets.
- [x] Node-RED nodes are shown directly as a visual section rather than only described in copy.
- [x] Phosphor icon library is used for interface icons.
- [x] Build and Sites packaging tests pass.
- [ ] Add the three real download URLs.

final result: passed
