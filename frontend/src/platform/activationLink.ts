import { appPath } from "../config/basePath";

const ACTIVATION_PATH = "/platform/activate";

export const platformActivationUrl = (
  token: string,
  origin = window.location.origin,
): string => {
  const url = new URL(appPath(ACTIVATION_PATH), origin);
  url.hash = new URLSearchParams({ token }).toString();
  return url.toString();
};

export const activationTokenFromHash = (hash: string): string => {
  const fragment = hash.startsWith("#") ? hash.slice(1) : hash;
  return new URLSearchParams(fragment).get("token") ?? "";
};
