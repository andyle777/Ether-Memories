import assert from "node:assert/strict";
import * as fs from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

assert.equal(process.platform, "win32", "T5 negative controls require native Windows");
const repo = fileURLToPath(new URL("../", import.meta.url));
const parent = await fs.mkdtemp(join(tmpdir(), "ether-t5-negative-"));
try {
  const preload = join(parent, "faults.mjs");
  await fs.writeFile(preload, `
    import { createRequire, syncBuiltinESMExports } from "node:module";
    const require = createRequire(import.meta.url);
    if (process.env.ETHER_T5_NEGATIVE_MODE === "junction") {
      require("node:fs/promises").symlink = async () => { const error = new Error("required junction probe unavailable"); error.code = "EPERM"; throw error; };
    } else if (process.env.ETHER_T5_NEGATIVE_MODE === "marker") {
      const cp = require("node:child_process"), original = cp.spawn;
      cp.spawn = () => original(process.execPath, ["-e", "process.exit(0)"], { stdio: ["ignore", "pipe", "pipe"] });
    }
    syncBuiltinESMExports();
  `);
  for (const [mode, script] of [["junction", "round11-windows-native-probe.mjs"], ["marker", "round11-windows-crash-probe.mjs"]]) {
    const work = join(parent, mode); await fs.mkdir(work);
    const child = spawnSync(process.execPath, ["--import", pathToFileURL(preload).href, join(repo, "scripts", script)], {
      cwd: work, encoding: "utf8", timeout: 90000,
      env: { ...process.env, ETHER_T5_NEGATIVE_MODE: mode }
    });
    assert.equal(child.error, undefined, `${mode}: controlled child must complete without a harness timeout`);
    assert.notEqual(child.status, 0, `${mode}: missing mandatory native evidence must fail the probe; stdout=${child.stdout}; stderr=${child.stderr}`);
    if (mode === "junction") {
      const report = JSON.parse(await fs.readFile(join(work, `round11-report-${process.version.replaceAll('.', '_')}.json`), "utf8"));
      assert.equal(report.ok, false);
      assert.ok(report.assertions.some(item => item.name === "junction creation is required" && item.ok === false), JSON.stringify(report));
    } else {
      assert.match(child.stderr, /Child exited before marker/, `Unexpected failure: ${child.stderr}`);
    }
  }
  console.log(JSON.stringify({ platform: process.platform, node: process.version, nativeProofNegativeControls: "passed",
    unavailableJunctionRejected: true, unmarkedChildRejected: true }));
} finally {
  await fs.rm(parent, { recursive: true, force: true });
}
