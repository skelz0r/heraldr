import { spawnSync } from "node:child_process";
import { createPrivateKey, createSign } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { connect } from "node:http2";
import { homedir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

const home = process.env.HERALDR_HOME ?? homedir();
const herdr = process.env.HERDR_BIN_PATH ?? "herdr";
const stateDir = process.env.HERALDR_STATE_DIR ?? join(home, ".local/state/heraldr");
const configDir = process.env.HERALDR_CONFIG_DIR ?? join(home, ".config/heraldr");
const claudeDir = join(home, ".claude");
const debounceMs = Number(process.env.HERALDR_NOTIFY_DEBOUNCE_MS ?? 3000);
const notificationBodyLength = 178;

const apnsHosts = {
  sandbox: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
};

function herdrJson(...args) {
  const result = spawnSync(herdr, args, { encoding: "utf8" });
  if (result.status !== 0) return null;
  try {
    return JSON.parse(result.stdout);
  } catch {
    return null;
  }
}

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

function markerPath(paneId) {
  return join(stateDir, "notified", Buffer.from(paneId).toString("base64url"));
}

function alreadyNotified(paneId) {
  try {
    statSync(markerPath(paneId));
    return true;
  } catch {
    return false;
  }
}

function rememberNotified(paneId) {
  mkdirSync(join(stateDir, "notified"), { recursive: true });
  writeFileSync(markerPath(paneId), "");
}

function forgetNotified(paneId) {
  rmSync(markerPath(paneId), { force: true });
}

function remoteControlUrl(sessionId) {
  const sessionsDir = join(claudeDir, "sessions");
  let names;
  try {
    names = readdirSync(sessionsDir);
  } catch {
    return null;
  }
  for (const name of names.filter((entry) => entry.endsWith(".json"))) {
    const session = readJson(join(sessionsDir, name));
    if (session?.sessionId === sessionId && typeof session.bridgeSessionId === "string") {
      return `https://claude.ai/code/${session.bridgeSessionId}`;
    }
  }
  return null;
}

function paneScreen(paneId) {
  const result = spawnSync(herdr, ["pane", "read", paneId, "--source", "recent-unwrapped", "--lines", "60"], { encoding: "utf8" });
  return result.status === 0 ? result.stdout.split("\n").map((line) => line.trim()) : [];
}

function dialogLines(screen) {
  const selected = screen.findLastIndex((line) => /^❯ \d+\./.test(line));
  if (selected < 0) return [];
  const top = screen.findLastIndex((line, index) => index < selected && /^─{10,}$/.test(line));
  return top < 0 ? [] : screen.slice(top + 1, selected);
}

function shorten(text) {
  return text.length > notificationBodyLength ? `${text.slice(0, notificationBodyLength - 1).trimEnd()}…` : text;
}

function pendingRequest(paneId) {
  const dialog = dialogLines(paneScreen(paneId));
  const question = dialog.filter((line) => line.startsWith("│")).map((line) => line.slice(1).trim());
  if (question.length > 0) return shorten(question.join(" "));
  const [title, ...rest] = dialog.filter((line) => line !== "");
  if (title === "Bash command") {
    const separator = rest.findIndex((line) => /^╌+$/.test(line));
    const description = rest.slice(0, separator < 0 ? 0 : separator).filter((line) => !line.startsWith("Tip:"));
    return description.length > 0 ? shorten(`Veut lancer : ${description.join(" ")}`) : "Veut lancer une commande";
  }
  const asking = rest.findLast((line) => line.startsWith("Do you want to "));
  if (!asking) return null;
  const edited = asking.match(/^Do you want to (?:make this edit to|overwrite) (.+)\?$/);
  if (edited) return shorten(`Veut modifier : ${edited[1]}`);
  const created = asking.match(/^Do you want to create (.+)\?$/);
  if (created) return shorten(`Veut créer : ${created[1]}`);
  return shorten(`Demande d'autorisation : ${title}`);
}

function apnsKey() {
  let names;
  try {
    names = readdirSync(configDir);
  } catch {
    return null;
  }
  const name = names.find((entry) => /^AuthKey_[A-Z0-9]{10}\.p8$/.test(entry));
  if (!name) return null;
  return { keyId: name.slice(8, 18), pem: readFileSync(join(configDir, name)) };
}

function providerToken(key, teamId) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const input = `${encode({ alg: "ES256", kid: key.keyId })}.${encode({ iss: teamId, iat: Math.floor(Date.now() / 1000) })}`;
  const signature = createSign("SHA256").update(input).sign({ key: createPrivateKey(key.pem), dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}

function postToApns(device, token, headers, body) {
  const origin = process.env.HERALDR_APNS_ORIGIN ?? apnsHosts[device.env];
  return new Promise((resolve, reject) => {
    const client = connect(origin);
    client.on("error", reject);
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${device.token}`,
      authorization: `bearer ${token}`,
      "apns-topic": device.topic,
      "apns-push-type": "alert",
      ...headers,
    });
    let status = 0;
    let answer = "";
    request.setEncoding("utf8");
    request.on("response", (response) => (status = response[":status"]));
    request.on("data", (chunk) => (answer += chunk));
    request.on("end", () => {
      client.close();
      resolve({ status, answer });
    });
    request.on("error", reject);
    request.end(JSON.stringify(body));
  });
}

async function main() {
  const event = JSON.parse(process.env.HERDR_PLUGIN_EVENT_JSON ?? "{}").data ?? {};
  const paneId = event.pane_id;
  if (typeof paneId !== "string") return;
  const blocked = String(event.agent_status).toLowerCase() === "blocked";
  if (blocked === alreadyNotified(paneId)) return;

  await sleep(debounceMs);
  const agent = herdrJson("agent", "get", paneId)?.result?.agent;
  if (!agent) {
    forgetNotified(paneId);
    return;
  }
  if ((agent.agent_status === "blocked") !== blocked) return;
  if (!blocked) {
    forgetNotified(paneId);
    return;
  }
  if (!agent.name?.endsWith("-main") || alreadyNotified(paneId)) return;

  const device = readJson(join(stateDir, "push-device.json"));
  const key = apnsKey();
  if (!device || !key) return;

  const label = herdrJson("workspace", "get", agent.workspace_id)?.result?.workspace?.label ?? agent.workspace_id;
  const sessionId = agent.agent_session?.value;
  const url = sessionId ? remoteControlUrl(sessionId) : null;
  const question = pendingRequest(paneId);
  const body = {
    aps: {
      alert: { title: label, subtitle: agent.name, body: question ?? "Attend une réponse" },
      sound: "default",
      "thread-id": agent.name,
    },
    workspace_id: agent.workspace_id,
    agent: agent.name,
    ...(url ? { session_url: url } : {}),
  };
  const response = await postToApns(device, providerToken(key, device.team), { "apns-collapse-id": agent.name }, body);
  if (response.status === 200) {
    rememberNotified(paneId);
  } else if (response.status === 410 || /BadDeviceToken|Unregistered/.test(response.answer)) {
    rmSync(join(stateDir, "push-device.json"), { force: true });
    throw new Error(`APNs a rejeté le token (${response.status} ${response.answer}), appareil oublié`);
  } else {
    throw new Error(`APNs ${response.status} ${response.answer}`);
  }
}

main().catch((error) => {
  console.error(`heraldr notify: ${error.message}`);
  process.exit(1);
});
