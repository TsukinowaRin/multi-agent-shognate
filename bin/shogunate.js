#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const repoRawBase = "https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main";
const bootstrapUrl = `${repoRawBase}/scripts/shogunate_package_bootstrap.sh`;

function usage() {
  console.log(`Usage:
  shogunate install [-- --version v5.0.0.12 --prefix ~/.shogunate/shogunate]
  shogunate run [args...]
  shogunate --help

Commands:
  install   Run the cURL-based package bootstrap.
  run       Run Shogunate-Runtime.sh from this package checkout.

The npm package is a thin wrapper. The canonical install path is:
  curl -fsSL ${bootstrapUrl} | bash
`);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    shell: false,
    ...options,
  });
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  process.exit(result.status ?? 0);
}

const args = process.argv.slice(2);
const command = args.shift();

if (!command || command === "-h" || command === "--help") {
  usage();
  process.exit(0);
}

if (command === "install") {
  const separator = args[0] === "--" ? args.shift() : null;
  void separator;
  const quotedArgs = args.map((arg) => `'${arg.replace(/'/g, "'\\''")}'`).join(" ");
  const shellCommand = `curl -fsSL '${bootstrapUrl}' | bash${quotedArgs ? ` -s -- ${quotedArgs}` : ""}`;
  run("bash", ["-lc", shellCommand]);
}

if (command === "run") {
  const root = path.resolve(__dirname, "..");
  run("bash", ["Shogunate-Runtime.sh", ...args], { cwd: root });
}

console.error(`Unknown command: ${command}`);
usage();
process.exit(64);
