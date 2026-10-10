import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http2";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { generateKeyPairSync } from "node:crypto";

const hook = join(dirname(fileURLToPath(import.meta.url)), "..", "notify-hook.mjs");
const debounceMs = 300;
const sessionId = "6b1d0c1e-0000-4000-8000-000000000001";

let apns;
let apnsAnswer;
let pushes;
let world;

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(value));
}

function setAgent({ name = "acme_app-main", status = "blocked" } = {}) {
  writeJson(join(world, "herdr", "agent.json"), {
    result: {
      agent: {
        name,
        pane_id: "w1:p2",
        workspace_id: "w1",
        agent_status: status,
        agent_session: { value: sessionId },
      },
    },
  });
}

function removeAgent() {
  rmSync(join(world, "herdr", "agent.json"), { force: true });
}

function askQuestion(question) {
  const toolUse = { type: "tool_use", name: "AskUserQuestion", input: { questions: [{ question, header: "Choix" }] } };
  writeFileSync(
    join(world, "home", ".claude", "projects", "-Users-me-work-acme", `${sessionId}.jsonl`),
    `${JSON.stringify({ type: "user", message: { content: "fais X" } })}\n${JSON.stringify({ type: "assistant", message: { content: [toolUse] } })}\n`,
  );
}

function runHook(status) {
  const event = { event: "pane_agent_status_changed", data: { pane_id: "w1:p2", workspace_id: "w1", agent_status: status } };
  return new Promise((resolve) => {
    const child = spawn(process.execPath, [hook], {
      env: {
        ...process.env,
        HERDR_BIN_PATH: join(world, "herdr", "herdr"),
        HERDR_PLUGIN_EVENT_JSON: JSON.stringify(event),
        HERALDR_HOME: join(world, "home"),
        HERALDR_NOTIFY_DEBOUNCE_MS: String(debounceMs),
        HERALDR_APNS_ORIGIN: `http://localhost:${apns.address().port}`,
      },
    });
    let stderr = "";
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("close", (code) => resolve({ code, stderr }));
  });
}

before(async () => {
  apns = createServer();
  apns.on("stream", (stream, headers) => {
    let body = "";
    stream.on("data", (chunk) => (body += chunk));
    stream.on("end", () => {
      pushes.push({ headers, body: JSON.parse(body) });
      stream.respond({ ":status": apnsAnswer.status });
      stream.end(apnsAnswer.body);
    });
  });
  await new Promise((resolve) => apns.listen(0, resolve));
});

after(() => apns.close());

beforeEach(() => {
  pushes = [];
  apnsAnswer = { status: 200, body: "" };
  world = mkdtempSync(join(tmpdir(), "heraldr-notify-"));
  const herdr = join(world, "herdr", "herdr");
  mkdirSync(dirname(herdr), { recursive: true });
  writeFileSync(
    herdr,
    `#!/bin/sh
case "$1 $2" in
  "agent get") cat "${join(world, "herdr", "agent.json")}" 2>/dev/null || exit 1 ;;
  "workspace get") echo '{"result":{"workspace":{"label":"acme_app"}}}' ;;
  *) exit 1 ;;
esac
`,
  );
  chmodSync(herdr, 0o755);
  const home = join(world, "home");
  mkdirSync(join(home, ".claude", "projects", "-Users-me-work-acme"), { recursive: true });
  writeJson(join(home, ".claude", "sessions", "4242.json"), {
    pid: 4242,
    sessionId,
    bridgeSessionId: "session_01ABCDEFGHIJKLMNOPQRSTUV",
  });
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  mkdirSync(join(home, ".config", "heraldr"), { recursive: true });
  writeFileSync(join(home, ".config", "heraldr", "AuthKey_ABCDE12345.p8"), privateKey.export({ type: "pkcs8", format: "pem" }));
  writeJson(join(home, ".local", "state", "heraldr", "push-device.json"), {
    token: "ab".repeat(32),
    env: "sandbox",
    topic: "com.skelz0r.heraldr.dev",
    team: "ABCDE12345",
  });
});

describe("notification d'un agent -main qui pose une question", () => {
  it("prévient l'iPhone avec le workspace, l'agent, la question et le lien de la session Remote Control", async () => {
    setAgent();
    askQuestion("Quelle base de données utiliser ?");

    const { code, stderr } = await runHook("blocked");

    assert.equal(code, 0, stderr);
    assert.equal(pushes.length, 1);
    const [push] = pushes;
    assert.equal(push.headers["apns-topic"], "com.skelz0r.heraldr.dev");
    assert.match(push.headers.authorization, /^bearer /);
    assert.deepEqual(push.body.aps.alert, {
      title: "acme_app",
      subtitle: "acme_app-main",
      body: "Quelle base de données utiliser ?",
    });
    assert.equal(push.body.session_url, "https://claude.ai/code/session_01ABCDEFGHIJKLMNOPQRSTUV");
    assert.equal(push.body.workspace_id, "w1");
    assert.equal(push.body.agent, "acme_app-main");
  });

  it("ignore les agents qui ne sont pas des -main, comme les Claude des worktrees", async () => {
    setAgent({ name: null });

    await runHook("blocked");

    assert.equal(pushes.length, 0);
  });

  it("ne prévient pas si l'agent n'est plus bloqué à la fin du debounce", async () => {
    setAgent();
    const running = runHook("blocked");
    await sleep(debounceMs / 3);
    setAgent({ status: "working" });

    await running;

    assert.equal(pushes.length, 0);
  });

  it("ne prévient qu'une fois tant que l'agent reste bloqué", async () => {
    setAgent();

    await runHook("blocked");
    await runHook("blocked");

    assert.equal(pushes.length, 1);
  });

  it("prévient de nouveau pour la question suivante, une fois l'agent reparti", async () => {
    setAgent();
    await runHook("blocked");
    setAgent({ status: "working" });
    await runHook("working");
    setAgent();

    await runHook("blocked");

    assert.equal(pushes.length, 2);
  });

  it("ne fait rien tant que l'iPhone n'a pas envoyé son token", async () => {
    setAgent();
    rmSync(join(world, "home", ".local", "state", "heraldr", "push-device.json"));

    await runHook("blocked");

    assert.equal(pushes.length, 0);
  });

  it("oublie le token qu'APNs déclare mort", async () => {
    setAgent();
    apnsAnswer = { status: 410, body: '{"reason":"Unregistered"}' };

    const { code } = await runHook("blocked");

    assert.equal(code, 1);
    assert.equal(existsSync(join(world, "home", ".local", "state", "heraldr", "push-device.json")), false);
  });

  it("se rabat sur un texte générique quand la question est introuvable", async () => {
    setAgent();

    await runHook("blocked");

    assert.equal(pushes[0].body.aps.alert.body, "Attend une réponse");
  });

  it("n'envoie pas de lien quand la session Remote Control est introuvable", async () => {
    setAgent();
    rmSync(join(world, "home", ".claude", "sessions"), { recursive: true });

    await runHook("blocked");

    assert.equal(pushes[0].body.session_url, undefined);
  });

  it("ne prévient pas pour un agent disparu", async () => {
    removeAgent();

    await runHook("blocked");

    assert.equal(pushes.length, 0);
  });
});
