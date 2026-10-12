import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http2";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { after, before, beforeEach, describe, it } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { fileURLToPath } from "node:url";
import { generateKeyPairSync } from "node:crypto";

const hook = join(dirname(fileURLToPath(import.meta.url)), "..", "notify-hook.mjs");
const dispatch = join(dirname(hook), "dispatch.sh");
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

function showScreen(...lines) {
  writeFileSync(join(world, "herdr", "screen.txt"), `${lines.join("\n")}\n`);
}

function showDialog(...lines) {
  showScreen("⏺ Bash(git status)", "  ⎿  On branch main", "", "─".repeat(80), ...lines, " Esc to cancel · Tab to amend");
}

function showQuestion(question) {
  showScreen(
    "⏺ Bash(git status)",
    "─".repeat(80),
    "←  ☐ Base  ✔ Submit  →",
    "",
    `│ ${question}`,
    "",
    "❯ 1. Postgres",
    "     Robuste et déjà en place.",
    "  2. SQLite",
    "  3. Type something.",
    "─".repeat(80),
    "  4. Chat about this",
    "",
    "Enter to select · Tab/Arrow keys to navigate · Esc to cancel",
  );
}

function lastToolAlreadyRun() {
  const toolUse = {
    type: "tool_use",
    id: "toolu_1",
    name: "Bash",
    input: { command: "git status", description: "Show working tree status" },
  };
  const toolResult = { type: "tool_result", tool_use_id: "toolu_1", content: "On branch main" };
  writeFileSync(
    join(world, "home", ".claude", "projects", "-Users-me-work-acme", `${sessionId}.jsonl`),
    [
      { type: "user", message: { content: "fais X" } },
      { type: "assistant", message: { content: [toolUse] } },
      { type: "user", message: { content: [toolResult] } },
    ]
      .map((entry) => `${JSON.stringify(entry)}\n`)
      .join(""),
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

function stateDir() {
  return join(world, "home", ".local", "state", "heraldr");
}

function runDispatch(args, input = "") {
  return new Promise((resolve) => {
    const child = spawn("/bin/sh", [join(stateDir(), "dispatch.sh"), ...args], {
      env: {
        ...process.env,
        PATH: `${join(world, "herdr")}:${process.env.PATH}`,
        HERALDR_STATE_DIR: stateDir(),
        HERALDR_HOME: join(world, "home"),
        HERALDR_APNS_ORIGIN: `http://localhost:${apns.address().port}`,
      },
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => (stdout += chunk));
    child.stderr.on("data", (chunk) => (stderr += chunk));
    child.on("close", (code) => resolve({ code, stdout, stderr }));
    child.stdin.end(input);
  });
}

async function sentQuestion(text) {
  mkdirSync(join(stateDir(), "plugin"), { recursive: true });
  copyFileSync(dispatch, join(stateDir(), "dispatch.sh"));
  copyFileSync(hook, join(stateDir(), "plugin", "notify-hook.mjs"));
  const label = Buffer.from("acme_app").toString("base64");
  const { stdout } = await runDispatch(["enqueue", "w1", "acme_app-main", label], text);
  return stdout.trim();
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
  "pane read") cat "${join(world, "herdr", "screen.txt")}" 2>/dev/null || exit 1 ;;
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
    showQuestion("Quelle base de données utiliser ?");

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

  it("lit la question à l'écran, le transcript n'ayant encore que l'outil lancé avant elle", async () => {
    setAgent();
    lastToolAlreadyRun();
    showQuestion("On garde le cache ou on le vide ?");

    await runHook("blocked");

    assert.equal(pushes[0].body.aps.alert.body, "On garde le cache ou on le vide ?");
  });

  it("décrit la commande qu'un Claude demande la permission de lancer", async () => {
    setAgent();
    lastToolAlreadyRun();
    showDialog(
      " Bash command",
      " Tip: auto mode handles these prompts for you",
      " Supprime les fichiers temporaires",
      "╌".repeat(80),
      " rm -rf tmp/cache",
      "╌".repeat(80),
      " Do you want to proceed?",
      " ❯ 1. Yes",
      "   2. No",
    );

    await runHook("blocked");

    assert.equal(pushes[0].body.aps.alert.body, "Veut lancer : Supprime les fichiers temporaires");
  });

  it("ne montre pas la commande brute quand elle n'a pas de description", async () => {
    setAgent();
    showDialog(" Bash command", "╌".repeat(80), " rm -rf tmp/cache", "╌".repeat(80), " Do you want to proceed?", " ❯ 1. Yes", "   2. No");

    await runHook("blocked");

    assert.equal(pushes[0].body.aps.alert.body, "Veut lancer une commande");
  });

  for (const [title, question, body] of [
    ["Edit file", "Do you want to make this edit to AppModel.swift?", "Veut modifier : AppModel.swift"],
    ["Overwrite file", "Do you want to overwrite spec.md?", "Veut modifier : spec.md"],
    ["Create file", "Do you want to create notes.md?", "Veut créer : notes.md"],
  ]) {
    it(`nomme le fichier visé par une permission « ${title} »`, async () => {
      setAgent();
      showDialog(` ${title}`, " docs/notes.md", "╌".repeat(80), "  1 +bonjour", "╌".repeat(80), ` ${question}`, " ❯ 1. Yes", "   2. No");

      await runHook("blocked");

      assert.equal(pushes[0].body.aps.alert.body, body);
    });
  }

  it("se rabat sur le titre de la demande pour un autre outil", async () => {
    setAgent();
    showDialog(" Fetch", " https://example.com", " Do you want to allow Claude to fetch this content?", " ❯ 1. Yes", "   2. No");

    await runHook("blocked");

    assert.equal(pushes[0].body.aps.alert.body, "Demande d'autorisation : Fetch");
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

describe("réponse d'un -main à une simple question", () => {
  const answer = "Le cache est vidé à chaque déploiement.\n\n## Détail\n\nLe job `purge` tourne après `deploy`.\n";

  it("garde la réponse sur le Mac et pousse son résumé à l'iPhone, rattaché à l'envoi", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?");

    const { code, stderr } = await runDispatch(["answer", jobId], answer);

    assert.equal(code, 0, stderr);
    assert.equal(stderr, "");
    assert.equal(pushes.length, 1);
    assert.deepEqual(pushes[0].body.aps.alert, {
      title: "acme_app",
      subtitle: "Réponse",
      body: "Le cache est vidé à chaque déploiement.",
    });
    assert.equal(pushes[0].body.kind, "answer");
    assert.equal(pushes[0].body.job_id, jobId);
    assert.equal(pushes[0].body.workspace_id, "w1");
    assert.equal(pushes[0].body.agent, "acme_app-main");
    assert.equal((await runDispatch(["read-answer", jobId])).stdout, answer);
  });

  it("signale l'envoi à l'app dans status une fois la réponse remise", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?");

    await runDispatch(["answer", jobId], answer);

    const line = (await runDispatch(["status"])).stdout.split("\n").find((entry) => entry.startsWith(jobId));
    assert.equal(line.split("\t")[5], "answered");
  });

  it("donne à Claude l'id de l'envoi à rappeler pour répondre", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?\n\nConsignes :\n- answer {{job_id}}");

    assert.match(readFileSync(join(stateDir(), "jobs", jobId, "prompt"), "utf8"), new RegExp(`- answer ${jobId}$`, "m"));
  });

  it("garde la réponse sans notification tant que l'iPhone n'a pas envoyé son token", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?");
    rmSync(join(stateDir(), "push-device.json"));

    const { code } = await runDispatch(["answer", jobId], answer);

    assert.equal(code, 0);
    assert.equal(pushes.length, 0);
    assert.equal((await runDispatch(["read-answer", jobId])).stdout, answer);
  });

  it("garde la réponse et oublie le token qu'APNs déclare mort", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?");
    apnsAnswer = { status: 410, body: '{"reason":"Unregistered"}' };

    const { code, stderr } = await runDispatch(["answer", jobId], answer);

    assert.equal(code, 0);
    assert.match(stderr, /notification non envoyée/);
    assert.equal(existsSync(join(stateDir(), "push-device.json")), false);
    assert.equal((await runDispatch(["read-answer", jobId])).stdout, answer);
  });

  it("refuse une réponse sans résumé ou pour un envoi inconnu", async () => {
    const jobId = await sentQuestion("Comment marche le cache ?");

    assert.equal((await runDispatch(["answer", jobId], "\nRéponse sans résumé")).code, 2);
    assert.equal((await runDispatch(["answer", "20261010120000-1-deadbeef"], answer)).code, 2);
    assert.equal((await runDispatch(["answer", "../../etc"], answer)).code, 2);
    assert.equal(pushes.length, 0);
  });
});
