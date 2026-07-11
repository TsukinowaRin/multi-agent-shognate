#!/usr/bin/env node
"use strict";

const { spawnSync } = require("node:child_process");
const path = require("node:path");

const repoRawBase = "https://raw.githubusercontent.com/TsukinowaRin/multi-agent-shognate/main";
const defaultBootstrapUrl = `${repoRawBase}/shogunate_mod/package/bootstrap.sh`;
const bootstrapUrl = process.env.SHOGUNATE_NPM_BOOTSTRAP_URL || defaultBootstrapUrl;

function usage() {
  console.log(`Usage:
  shogunate install [-- --version v5.0.0.12 --prefix ~/.shogunate/shogunate]
  shogunate run [args...]
  shogunate pair [args...]
  shogunate projects [list|add|select|current|remove]
  shogunate battlefield [list|status|start|stop|send|outbox|sessions|transcript]
  shogunate app [capabilities|list|status|start|stop|send|outbox|sessions|transcript]
  shogunate help
  shogunate --help

Commands:
  install   Run the cURL-based package bootstrap.
  run       Run the Shogunate MOD runtime launcher for the current project directory.
  pair      Pair Android app over USB auto + Tailscale/LAN for the current project.
  projects  Manage the registered project list.
  battlefield  Manage registered project runtimes, offline history, and pending messages.
  app       JSON-friendly API for mobile and desktop apps.

The npm package is a thin wrapper. Its install command runs the MOD package bootstrap:
  curl -fsSL ${bootstrapUrl} | bash
Set SHOGUNATE_NPM_BOOTSTRAP_URL to test or mirror the bootstrap script.
Set SHOGUNATE_PAIR_PASSWORD to require a fixed local approval password.
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

function main(argv = process.argv.slice(2), cwd = process.cwd()) {
  const args = [...argv];
  const command = args.shift();
  const root = path.resolve(__dirname, "../..");
  const venvBin = path.join(root, ".venv", "bin");
  const commonUnixBins = [
    venvBin,
    "/opt/homebrew/opt/coreutils/libexec/gnubin",
    "/opt/homebrew/bin",
    "/usr/local/bin",
  ];
  const runtimeEnv = {
    ...process.env,
    PATH: `${commonUnixBins.join(path.delimiter)}${path.delimiter}${process.env.PATH || ""}`,
  };

  if (!command || command === "help" || command === "-h" || command === "--help") {
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
    run("bash", [path.join(root, "shogunate_mod/runtime/runtime_launcher.sh"), "--project", cwd, ...args], {
      env: runtimeEnv,
    });
  }

  if (command === "pair") {
    run("python3", [
      path.join(root, "shogunate_mod/pair/server.py"),
      "--project-root",
      root,
      "--target-project",
      cwd,
      ...args,
    ], { env: runtimeEnv });
  }

  if (command === "projects" || command === "project") {
    run("python3", [path.join(root, "shogunate_mod/projects/registry.py"), ...args], { env: runtimeEnv });
  }

  if (command === "battlefield" || command === "battlefields" || command === "app") {
    run("python3", [path.join(root, "shogunate_mod/battlefield/api.py"), ...args], {
      env: {
        ...runtimeEnv,
        SHOGUNATE_ENGINE_DIR: root,
        SHOGUNATE_COMMAND: process.argv[1],
      },
    });
  }

  console.error(`Unknown command: ${command}`);
  usage();
  process.exit(64);
}

if (require.main === module) {
  main();
}

module.exports = { main };
