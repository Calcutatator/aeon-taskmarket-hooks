#!/usr/bin/env node
// Narrow Aeon-compatible launcher for the reviewed staging and deployment scripts.
// Aeon's write tier permits `node` but not arbitrary community-pack Bash paths.
// This launcher exposes only fixed actions, hash-checks both bundled scripts, and
// strips credentials from the staging subprocess.

import { createHash } from "node:crypto";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const stageScript = join(scriptDir, "stage.sh");
const deployScript = join(scriptDir, "taskmarket-hook-deploy.sh");
const expectedHashes = new Map([
  [stageScript, "10c42f1b71d54b55d9aa59f7a96cc4cd396c5e0c130b59559ebc7bddf822b9db"],
  [deployScript, "60f67774f639eb6079dded3b11e8c30725bc8dc4012f9b44af2586d76286b8b4"],
]);
const buildSentinel = "aeon-taskmarket-hooks:1.0.0";

function fail(message, code = 2) {
  console.error(`deploy-taskmarket-hook launcher: ${message}`);
  process.exit(code);
}

function sha256(file) {
  return createHash("sha256").update(readFileSync(file)).digest("hex");
}

function verifyScripts() {
  for (const [file, expected] of expectedHashes) {
    if (!existsSync(file)) fail(`missing reviewed script: ${file}`, 3);
    const observed = sha256(file);
    if (observed !== expected) {
      fail(`reviewed script hash mismatch: ${file}\n  expected ${expected}\n  observed ${observed}`, 3);
    }
  }
}

function stateFile() {
  const tempBase = process.env.RUNNER_TEMP || process.env.TMPDIR || tmpdir();
  return process.env.TASKMARKET_HOOKBUILD_STATE_FILE || join(tempBase, "aeon-taskmarket-hookbuild.active");
}

function activeBuildDir() {
  const state = stateFile();
  if (!existsSync(state)) fail("no active build; run `node .../run.mjs stage` first", 3);
  const candidate = readFileSync(state, "utf8").trim();
  if (!candidate || !existsSync(candidate)) fail(`active build is unavailable: ${candidate || "<empty>"}`, 3);
  const resolved = realpathSync(candidate);
  const sentinel = join(resolved, ".aeon-taskmarket-hookbuild");
  if (!existsSync(sentinel) || readFileSync(sentinel, "utf8").trim() !== buildSentinel) {
    fail(`active build lacks the expected ownership sentinel: ${resolved}`, 3);
  }
  return resolved;
}

function runBash(script, args, env) {
  const result = spawnSync("bash", [script, ...args], { env, stdio: "inherit" });
  if (result.error) fail(result.error.message, 3);
  if (result.signal) fail(`subprocess terminated by ${result.signal}`, 3);
  process.exit(result.status ?? 3);
}

const [action, ...args] = process.argv.slice(2);
const validActions = new Set(["stage", "build-dir", "chains", "simulate", "broadcast"]);
if (!validActions.has(action) || args.length > 1) {
  fail("usage: run.mjs <stage|build-dir|chains|simulate|broadcast> [base-sepolia|base]");
}

verifyScripts();

if (action === "build-dir") {
  if (args.length) fail("build-dir accepts no chain argument");
  console.log(activeBuildDir());
  process.exit(0);
}

if (action === "stage") {
  if (args.length) fail("stage accepts no chain argument");
  const stagingEnv = { ...process.env };
  for (const name of [
    "HOOK_DEPLOYER_PRIVATE_KEY",
    "ALCHEMY_API_KEY",
    "ETHERSCAN_API_KEY",
    "XAI_API_KEY",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "GH_GLOBAL",
    "GH_READ_PAT",
  ]) {
    delete stagingEnv[name];
  }
  runBash(stageScript, [], stagingEnv);
}

const chain = args[0];
if (chain && chain !== "base-sepolia" && chain !== "base") {
  fail(`unsupported chain: ${chain}`);
}
if (action !== "chains") activeBuildDir();
if (action === "broadcast" && !String(process.env.SKILL_VAR || "").startsWith("arm:")) {
  fail("broadcast blocked: raw SKILL_VAR does not begin with arm:", 9);
}
runBash(deployScript, [action, ...(chain ? [chain] : [])], process.env);
