// vite.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    environment: "jsdom",
    // V8 coverage plus several jsdom/React Query suites exhaust the host when
    // Vitest fans out more workers, making otherwise-fast assertions hit the
    // default 5 s timeout. Cap concurrency instead of weakening that timeout.
    maxWorkers: 2,
    setupFiles: "./src/test/setup.ts",
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,tsx}"],
      exclude: [
        "src/**/*.{test,spec}.{ts,tsx}",
        "src/**/*.d.ts",
        "src/test/**",
      ],
      reportsDirectory: "coverage/release",
      reporter: ["text", "json", "json-summary", "lcov", "html"],
      reportOnFailure: true,
      thresholds: {
        lines: 85,
        branches: 80,
        statements: 85,
        "src/platform/platformApi.ts": {
          lines: 90,
          branches: 80,
          statements: 90,
        },
        "src/platform/StepUpProvider.tsx": {
          lines: 90,
        },
        "src/platform/stepUpContext.ts": {
          lines: 90,
        },
        "src/api/authSession.ts": {
          lines: 90,
        },
        "src/api/axiosConfig.ts": {
          lines: 90,
        },
        "src/hooks/context/auth-context.ts": {
          lines: 90,
        },
        "src/hooks/context/authContext.tsx": {
          lines: 90,
        },
        "src/hooks/context/useAuth.ts": {
          lines: 90,
        },
        "src/rutas/ProtectedRoute.tsx": {
          lines: 90,
          branches: 80,
          statements: 90,
        },
      },
    },
  },
  resolve: { alias: { "@": path.resolve(__dirname, "./src") } },
  build: {
    cssCodeSplit: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ["react", "react-dom", "react-router"],
          form: ["formik", "yup"],
          toast: ["react-toastify"],
        },
      },
    },
  },
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api/, ""),
      },
    },
  },
});
