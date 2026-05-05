import { mkdirSync } from "node:fs";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const packageJson = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8")
);

mkdirSync("dist", { recursive: true });

const output = `dist/${packageJson.name}-${packageJson.version}.vsix`;
const result = spawnSync(
  "npx",
  ["--yes", "@vscode/vsce", "package", "--out", output],
  {
    stdio: "inherit",
    shell: process.platform === "win32",
  }
);

process.exit(result.status ?? 1);
