import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const API_ORIGIN_PLACEHOLDER = "__GESTUDIO_API_ORIGIN__";

export function resolveApiOrigin(apiBaseUrl) {
  const configured = apiBaseUrl?.trim();
  if (!configured) {
    throw new Error("VITE_API_BASE_URL es obligatoria para generar _headers de Pages");
  }

  let url;
  try {
    url = new URL(configured);
  } catch (error) {
    throw new Error("VITE_API_BASE_URL no es una URL válida", { cause: error });
  }

  const isLocal = ["localhost", "127.0.0.1"].includes(url.hostname);
  if (url.protocol !== "https:" && !(isLocal && url.protocol === "http:")) {
    throw new Error("VITE_API_BASE_URL debe usar HTTPS fuera de localhost");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error("VITE_API_BASE_URL no puede incluir credenciales, query ni fragmento");
  }

  return url.origin;
}

export function renderPagesHeaders(template, apiBaseUrl) {
  const occurrences = template.split(API_ORIGIN_PLACEHOLDER).length - 1;
  if (occurrences !== 1) {
    throw new Error(
      `La plantilla _headers debe contener exactamente una vez ${API_ORIGIN_PLACEHOLDER}`,
    );
  }

  const rendered = template.replace(
    API_ORIGIN_PLACEHOLDER,
    resolveApiOrigin(apiBaseUrl),
  );

  const oversizedLine = rendered
    .split(/\r?\n/)
    .find((line) => line.length > 2000);
  if (oversizedLine) {
    throw new Error("_headers contiene una línea superior a 2000 caracteres");
  }

  return rendered.endsWith("\n") ? rendered : `${rendered}\n`;
}

export async function generatePagesHeaders({
  apiBaseUrl = process.env.VITE_API_BASE_URL,
  templatePath,
  outputPath,
} = {}) {
  const frontendRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const source = templatePath ?? resolve(frontendRoot, "public", "_headers");
  const destination = outputPath ?? resolve(frontendRoot, "dist", "_headers");
  const template = await readFile(source, "utf8");
  await writeFile(destination, renderPagesHeaders(template, apiBaseUrl), "utf8");
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  await generatePagesHeaders();
}
