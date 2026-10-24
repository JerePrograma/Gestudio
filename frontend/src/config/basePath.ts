export const appPath = (
  path: string,
  base = import.meta.env.BASE_URL,
): string => `${base.replace(/\/$/, "")}/${path.replace(/^\//, "")}`;

export const stripAppBase = (
  path: string,
  base = import.meta.env.BASE_URL,
): string => {
  const prefix = base.replace(/\/$/, "");
  return prefix && (path === prefix || path.startsWith(`${prefix}/`))
    ? path.slice(prefix.length) || "/"
    : path;
};
