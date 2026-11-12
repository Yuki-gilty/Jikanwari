import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
export default defineConfig({
  plugins: [cloudflareTest({
    wrangler: { configPath: "./wrangler.jsonc" },
    miniflare: { bindings: { APP_TOKEN: "test-app-token", ANTHROPIC_API_KEY: "test-provider-key" } },
  })],
});
