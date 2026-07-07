/// <reference types="vite/client" />

interface Window {
  requestIdleCallback?: (callback: IdleRequestCallback) => number;
  cancelIdleCallback?: (handle: number) => void;
}

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string;
  readonly VITE_APP_TIME_ZONE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}