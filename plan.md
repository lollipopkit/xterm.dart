# Optimization Plan for xterm.dart

## xterm.js/src Inspiration Notes

- **common/buffer/BufferLine.ts** — Uses compact `Uint32Array` storage per cell (content/fg/bg) with auxiliary maps for combined glyphs and extended attributes. Highlights the value of fixed-width memory layouts, lazily allocated maps, and recycling `CellData` instances to avoid GC thrash during scrollback mutations.
- **browser/renderer/dom/DomRenderer.ts** — Injects scoped CSS at runtime, pre-allocates row elements, and centralizes render dimension calculations tied to device pixel ratio. Emphasizes caching text metrics (`WidthCache`) and theme-driven style sheets to minimize DOM churn while keeping selection overlays isolated.
- **browser/services/CoreBrowserService.ts** — Provides a DPI monitor that re-attaches `matchMedia` listeners when the window changes and caches focus state per microtask. Suggests mirroring device pixel ratio watchers and batched focus recomputation on the Dart side to reduce redundant layout work.
- **common/input/TextDecoder.ts** — Implements streaming UTF-32 helpers and lightweight surrogate handling to keep input decoding allocation-free. Indicates potential wins from pooling buffers and skipping redundant guard rails when decoding trusted terminal streams.
- **common/input/Keyboard.ts** — Maps modifier combinations to CSI/SS3 sequences with explicit Alt-as-meta fallbacks, plus macOS composition edge cases. Offers a reference for normalizing keyboard behavior (especially Alt/Option handling and dead keys) across platforms.

## Proposed Optimization Roadmap

1. **Buffer storage audit** — Prototype a typed-data backed cell store in `lib/src/core/buffer` mirroring the three-slot layout, with benchmarks to evaluate GC pressure and scroll performance.
2. **Render metrics caching** — Introduce a `CharMetricsCache` layer in the Flutter renderer that lazily recomputes width/height on DPI or font option changes, inspired by `WidthCache` + `_updateDimensions`.
3. **DPR/focus observer** — Add a platform service to watch `MediaQueryData.devicePixelRatio`/focus changes and throttle viewport rebuilds akin to `CoreBrowserService`.
4. **Streaming decoders** — Replace ad-hoc UTF handling in the Dart parser with reusable streaming decoders (possibly backed by `Uint32List`) to cut conversions for paste bursts and zmodem transfers.
5. **Keyboard normalization** — Align keyboard mapping tables with xterm.js (including Alt+dead key paths) to eliminate drift between web and Dart engines.

## Immediate Next Steps

- Draft spike tickets for items 1–3, including benchmark coverage (`bin/xterm_bench.dart`) and targeted tests under `test/src/core`.
- Schedule follow-up passes to refine decoder and keyboard layers once buffer/render changes land.
