/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly MERMAID_DOCS_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
