import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import ts from "typescript";

const frontendRoot = path.resolve(import.meta.dirname, "..");
const repoRoot = path.resolve(frontendRoot, "..");

const readOption = (name) => {
  const index = process.argv.indexOf(name);
  if (index === -1 || !process.argv[index + 1]) {
    throw new Error(`Falta la opción obligatoria ${name}.`);
  }
  return path.resolve(process.argv[index + 1]);
};

const optionalOption = (name) => {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : path.resolve(process.argv[index + 1]);
};

const normalize = (value) => path.resolve(value).replaceAll("\\", "/").toLowerCase();
const repoRelative = (value) => path.relative(repoRoot, value).replaceAll("\\", "/");

const collectProductSources = (directory) => fs.readdirSync(directory, { withFileTypes: true })
  .flatMap((entry) => {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (absolute === path.join(frontendRoot, "src", "test")) {
        return [];
      }
      return collectProductSources(absolute);
    }
    if (!/\.(ts|tsx)$/.test(entry.name) ||
        /\.(test|spec)\.(ts|tsx)$/.test(entry.name) ||
        entry.name.endsWith(".d.ts")) {
      return [];
    }
    return [absolute];
  });

const emitsRuntimeCode = (sourcePath) => {
  const source = fs.readFileSync(sourcePath, "utf8");
  const output = ts.transpileModule(source, {
    fileName: sourcePath,
    compilerOptions: {
      target: ts.ScriptTarget.ES2022,
      module: ts.ModuleKind.ESNext,
      jsx: ts.JsxEmit.ReactJSX,
      importsNotUsedAsValues: ts.ImportsNotUsedAsValues.Remove,
    },
  }).outputText;
  const emitted = ts.createSourceFile(
    sourcePath.replace(/\.tsx?$/, ".js"),
    output,
    ts.ScriptTarget.ES2022,
    false,
    ts.ScriptKind.JS,
  );
  return emitted.statements.some((statement) =>
    !(ts.isExportDeclaration(statement) &&
      !statement.moduleSpecifier &&
      (!statement.exportClause || statement.exportClause.elements.length === 0)),
  );
};

const mapSize = (value) => value && typeof value === "object" ? Object.keys(value).length : 0;

const coveragePath = readOption("--coverage");
const statusPath = optionalOption("--status");
const outputPath = optionalOption("--output");
const coverage = JSON.parse(fs.readFileSync(coveragePath, "utf8"));
const coverageByPath = new Map(
  Object.entries(coverage).map(([file, entry]) => [normalize(file), entry]),
);

let expectedSources;
if (statusPath) {
  const status = JSON.parse(fs.readFileSync(statusPath, "utf8"));
  expectedSources = (status.changedSourceFiles ?? []).map((file) => path.resolve(repoRoot, file));
} else {
  expectedSources = collectProductSources(path.join(frontendRoot, "src"));
}
expectedSources.sort((left, right) => left.localeCompare(right));

const runtimeFiles = [];
const typeOnlyFiles = [];
const missingExecutableFiles = [];
const emptyExecutableMapFiles = [];

for (const sourcePath of expectedSources) {
  if (!fs.existsSync(sourcePath)) {
    throw new Error(`La fuente esperada no existe: ${repoRelative(sourcePath)}`);
  }
  const relative = repoRelative(sourcePath);
  if (!emitsRuntimeCode(sourcePath)) {
    typeOnlyFiles.push(relative);
    continue;
  }
  runtimeFiles.push(relative);
  const entry = coverageByPath.get(normalize(sourcePath));
  if (!entry) {
    missingExecutableFiles.push(relative);
    continue;
  }
  if (mapSize(entry.statementMap) === 0 && mapSize(entry.fnMap) === 0 && mapSize(entry.branchMap) === 0) {
    emptyExecutableMapFiles.push(relative);
  }
}

const evidence = {
  schemaVersion: 1,
  coverageMap: repoRelative(coveragePath),
  expectedSourceFiles: expectedSources.length,
  runtimeFiles,
  typeOnlyFiles,
  missingExecutableFiles,
  emptyExecutableMapFiles,
  passed: missingExecutableFiles.length === 0 && emptyExecutableMapFiles.length === 0,
};

if (outputPath) {
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`, "utf8");
}

if (!evidence.passed) {
  const problems = [
    ...missingExecutableFiles.map((file) => `${file} (ausente)`),
    ...emptyExecutableMapFiles.map((file) => `${file} (mapas vacíos)`),
  ];
  throw new Error(`Cobertura sin instrumentación ejecutable: ${problems.join(", ")}`);
}

console.log(
  `Coverage source inventory: PASS (${runtimeFiles.length} ejecutables, ${typeOnlyFiles.length} sólo tipos).`,
);
