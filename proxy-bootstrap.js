#!/usr/bin/env node
"use strict";
/**
 * Standalone bootstrap: fetch encrypted payload from URL, decrypt, extract.
 * Run on Ubuntu server. Requires: Node 18+, curl or https.
 *
 *   PAYLOAD_URL=https://raw.githubusercontent.com/USER/bin/main/proxy-payload.bin \
 *   HOME_PROXY_API_KEY=yourkey node proxy-bootstrap.js
 *
 * Or: node proxy-bootstrap.js <PAYLOAD_URL>
 */
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const readline = require("readline");
const { execFileSync } = require("child_process");

const ALGORITHM = "aes-256-gcm";
const KEY_LEN = 32;
const IV_LEN = 16;
const SALT_LEN = 32;
const TAG_LEN = 16;

function deriveKey(password, salt) {
  return crypto.scryptSync(password, salt, KEY_LEN);
}

function decrypt(raw, password) {
  const salt = raw.subarray(0, SALT_LEN);
  const iv = raw.subarray(SALT_LEN, SALT_LEN + IV_LEN);
  const tag = raw.subarray(SALT_LEN + IV_LEN, SALT_LEN + IV_LEN + TAG_LEN);
  const encrypted = raw.subarray(SALT_LEN + IV_LEN + TAG_LEN);
  const key = deriveKey(password, salt);
  const decipher = crypto.createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

function fetchUrl(url, destPath) {
  execFileSync("curl", ["-fsSL", "-o", destPath, "-L", url], { stdio: "inherit" });
  return fs.readFileSync(destPath);
}

function main() {
  const apiKey = process.env.HOME_PROXY_API_KEY;
  const payloadUrl = process.env.PAYLOAD_URL || process.argv[2];
  if (!apiKey) {
    console.error("HOME_PROXY_API_KEY must be set.");
    process.exit(1);
  }
  if (!payloadUrl) {
    console.error("Usage: PAYLOAD_URL=<raw-url> HOME_PROXY_API_KEY=<key> node proxy-bootstrap.js");
    console.error("   or: node proxy-bootstrap.js <PAYLOAD_URL>");
    process.exit(1);
  }
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), "home-proxy-"));
  fs.chmodSync(workDir, 0o700);
  try {
    console.log("Fetching payload...");
    const encPath = path.join(workDir, "proxy-payload.bin");
    const raw = fetchUrl(payloadUrl, encPath);
    fs.chmodSync(encPath, 0o600);
    console.log("Decrypting...");
    const decrypted = decrypt(raw, apiKey);
    const tarPath = path.join(workDir, "payload.tar.gz");
    fs.writeFileSync(tarPath, decrypted, { mode: 0o600 });
    fs.chmodSync(tarPath, 0o600);
    execFileSync("tar", ["-xzf", tarPath, "-C", workDir]);
    fs.unlinkSync(tarPath);
    fs.unlinkSync(encPath);
    const installDir = path.join(workDir, "home-proxy-payload");
    if (!fs.existsSync(installDir)) {
      console.error("Payload did not contain home-proxy-payload/");
      process.exit(1);
    }
    console.log("");
    console.log("Payload extracted to", installDir);
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question("Install the service now? (y/n) ", (answer) => {
      rl.close();
      if (answer && (answer.toLowerCase() === "y" || answer.toLowerCase() === "yes")) {
        try {
          execFileSync("sudo", ["-E", "bash", "scripts/install.sh"], {
            cwd: installDir,
            stdio: "inherit",
            env: process.env,
          });
        } catch (e) {
          process.exit(e.status || 1);
        }
      } else {
        console.log("");
        console.log("To install manually:");
        console.log("  cd", installDir);
        console.log("  export HOME_PROXY_API_KEY=your_key");
        console.log("  sudo -E bash scripts/install.sh");
      }
    });
  } catch (err) {
    console.error("Error:", err.message);
    process.exit(1);
  }
}

main();
