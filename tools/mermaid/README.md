# Mermaid Editor

A minimal, self-contained local editor for [Mermaid](https://mermaid.js.org) diagrams. Edit Mermaid code and config on the left, see the diagram render live on the right.

Forked from [mermaid-live-editor](https://github.com/mermaid-js/mermaid-live-editor) and pared down to a local-only tool — no accounts, cloud sync, analytics, or external services.

## Features

- Live preview of flowcharts, sequence diagrams, gantt charts, and every other Mermaid diagram type.
- Code and config editing with a Monaco editor (syntax highlighting, JSON schema validation for config).
- Pan, zoom, and reset the diagram view, plus a collapsible editor pane.
- Hand-drawn (rough) rendering and background-grid toggles.
- Export as PNG (with configurable size), SVG, or copy the image to the clipboard.
- Diagram state is persisted to `localStorage` and encoded in the URL hash, so reloading or sharing a link restores your work.

## Requirements

- [Node.js](https://nodejs.org/) (current LTS)
- [pnpm](https://pnpm.io/) — enable with `corepack enable pnpm`

## Development

```sh
pnpm install
pnpm dev
```

Then open the URL printed in the terminal (defaults to http://localhost:3000).

## Build

```sh
pnpm build      # static build, output in ./build
pnpm preview    # preview the production build
```

The app is built with SvelteKit and `@sveltejs/adapter-static`, so the output is a fully static site you can host anywhere.

## Checks

```sh
pnpm check      # svelte-check (type checking)
pnpm lint       # prettier + eslint
pnpm test       # vitest unit tests
```
