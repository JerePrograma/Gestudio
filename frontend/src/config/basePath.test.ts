import { describe, expect, it } from "vitest";
import { appPath, stripAppBase } from "./basePath";

describe("deployment base path", () => {
  it("preserves root deployments", () => {
    expect(appPath("/login", "/")).toBe("/login");
    expect(stripAppBase("/platform/login", "/")).toBe("/platform/login");
  });

  it("keeps tenant and platform navigation under the deployment prefix", () => {
    expect(appPath("/login", "/gestudio/")).toBe("/gestudio/login");
    expect(appPath("platform/activate", "/gestudio/")).toBe("/gestudio/platform/activate");
    expect(appPath("/", "/gestudio/")).toBe("/gestudio/");
    expect(stripAppBase("/gestudio/platform/login", "/gestudio/"))
      .toBe("/platform/login");
    expect(stripAppBase("/gestudio", "/gestudio/")).toBe("/");
  });

  it("does not strip another application with a common name prefix", () => {
    expect(stripAppBase("/gestudio-api/api", "/gestudio/"))
      .toBe("/gestudio-api/api");
  });
});
