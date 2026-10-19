import { spawnSync } from "node:child_process";
import { createHash, createPrivateKey, createSign } from "node:crypto";
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
const replySettleMs = Number(process.env.HERALDR_REPLY_SETTLE_MS ?? 800);
const maximumActions = 4;
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
  return result.status === 0 ? result.stdout.split("\n").map((line) => line.trimEnd()) : [];
}

const separatorPattern = /^─{10,}$/;
const questionTabsPattern = /^(?:←\s+)?[☐☒✔]\s/;
const optionPattern = /^(❯ | {2})(\d+)\.\s+(.*)$/;

function dialogLines(screen) {
  const selected = screen.findLastIndex((line) => /^❯ \d+\./.test(line));
  if (selected < 0) return [];
  const top = screen.findLastIndex((line, index) => index < selected && separatorPattern.test(line));
  return top < 0 ? [] : screen.slice(top + 1, selected);
}

function shorten(text) {
  return text.length > notificationBodyLength ? `${text.slice(0, notificationBodyLength - 1).trimEnd()}…` : text;
}

function shortenFromStart(text) {
  return text.length > notificationBodyLength ? `…${text.slice(text.length - notificationBodyLength + 1).trimStart()}` : text;
}

function claudeMessages(screen) {
  const messages = [];
  screen.forEach((line, index) => {
    if (!line.startsWith("⏺ ")) return;
    const end = screen.findIndex((next, after) => after > index && next !== "" && !next.startsWith("  "));
    const lines = [line.slice(2), ...screen.slice(index + 1, end < 0 ? screen.length : end)].map((entry) => entry.trim());
    const toolCall = /^[\w.:-]+\(/.test(lines[0]) || lines.some((entry) => entry.startsWith("⎿"));
    if (!toolCall) messages.push(lines.filter((entry) => entry !== "").join(" "));
  });
  return messages;
}

function lastClaudeMessage(screen) {
  const message = claudeMessages(screen).at(-1);
  return message ? shortenFromStart(message) : null;
}

function questionOptions(lines) {
  const options = [];
  for (const line of lines) {
    if (separatorPattern.test(line.trim())) break;
    const match = line.match(optionPattern);
    if (!match || Number(match[2]) !== options.length + 1) continue;
    options.push({
      number: Number(match[2]),
      label: match[3].replace(/\s{2,}[┌│└].*$/, "").trim(),
      cursor: match[1] === "❯ ",
      preview: /\s{2,}[┌│└]/.test(match[3]),
    });
  }
  return options;
}

function answerableOptions(options) {
  if (options.some((option) => /^\[.\]\s/.test(option.label))) return [];
  const choices = options.filter((option) => !/^Type something\.?$/.test(option.label));
  return choices.length <= maximumActions ? choices.map(({ number, label }) => ({ number, label })) : [];
}

function askedQuestion(screen, blockedSince = null) {
  const first = screen.findLastIndex((line) => /^(?:❯ | {2})1\.\s/.test(line));
  if (first < 0) return null;
  const top = screen.findLastIndex((line, index) => index < first && separatorPattern.test(line));
  if (top < 0) return null;
  if (screen.slice(first).some((line) => line.startsWith("⏺"))) return null;
  const [tabs, ...lines] = screen
    .slice(top + 1, first)
    .map((line) => line.trim().replace(/^│\s*/, ""))
    .filter((line) => line !== "");
  if (!questionTabsPattern.test(tabs ?? "")) return null;
  const text =
    lines[0] === "Review your answers"
      ? `Submit your answers? ${lines
          .filter((line) => line.startsWith("→"))
          .map((line) => line.slice(1).trim())
          .join(" · ")}`
      : lines.join(" ");
  const options = questionOptions(screen.slice(first));
  const id = createHash("sha256")
    .update(JSON.stringify([blockedSince, tabs, lines, options.map((option) => option.label)]))
    .digest("hex")
    .slice(0, 16);
  const choices = Number.isInteger(blockedSince) ? answerableOptions(options) : [];
  return { id, text, options, choices, preview: options.some((option) => option.preview) };
}

function pendingRequest(screen) {
  const question = askedQuestion(screen);
  if (question) return shorten(question.text);
  const dialog = dialogLines(screen.map((line) => line.trim()));
  const [title, ...rest] = dialog.filter((line) => line !== "");
  if (title === "Bash command") {
    const separator = rest.findIndex((line) => /^╌+$/.test(line));
    const description = rest.slice(0, separator < 0 ? 0 : separator).filter((line) => !line.startsWith("Tip:"));
    return description.length > 0 ? shorten(`Wants to run: ${description.join(" ")}`) : "Wants to run a command";
  }
  const asking = rest.findLast((line) => line.startsWith("Do you want to "));
  if (!asking) return null;
  const edited = asking.match(/^Do you want to (?:make this edit to|overwrite) (.+)\?$/);
  if (edited) return shorten(`Wants to edit: ${edited[1]}`);
  const created = asking.match(/^Do you want to create (.+)\?$/);
  if (created) return shorten(`Wants to create: ${created[1]}`);
  return shorten(`Permission request: ${title}`);
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
  const signature = createSign("SHA256")
    .update(input)
    .sign({ key: createPrivateKey(key.pem), dsaEncoding: "ieee-p1363" });
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

function sessionTopic(agent) {
  const title = typeof agent.terminal_title_stripped === "string" ? agent.terminal_title_stripped.trim() : "";
  return title === "" || title === "Claude Code" || title === agent.name ? null : title;
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

  if (await notify(paneId, agent)) rememberNotified(paneId);
}

async function notify(paneId, agent, screen = paneScreen(paneId)) {
  const device = readJson(join(stateDir, "push-device.json"));
  const key = apnsKey();
  if (!device || !key) return false;

  const label = herdrJson("workspace", "get", agent.workspace_id)?.result?.workspace?.label ?? agent.workspace_id;
  const sessionId = agent.agent_session?.value;
  const url = sessionId ? remoteControlUrl(sessionId) : null;
  const asked = askedQuestion(screen, agent.state_change_seq);
  const question = pendingRequest(screen) ?? lastClaudeMessage(screen);
  const topic = sessionTopic(agent);
  const answerable = asked && asked.choices.length > 0;
  const body = {
    aps: {
      alert: { title: label, ...(topic ? { subtitle: topic } : {}), body: question ?? "Waiting for an answer" },
      sound: "default",
      "thread-id": agent.name,
      ...(answerable ? { "mutable-content": 1 } : {}),
    },
    workspace_id: agent.workspace_id,
    agent: agent.name,
    ...(url ? { session_url: url } : {}),
    ...(answerable ? { pane_id: paneId, question_id: asked.id, options: asked.choices } : {}),
  };
  await deliver(device, key, { "apns-collapse-id": agent.name }, body);
  return true;
}

class ReplyRefused extends Error {
  constructor(message, exitCode) {
    super(message);
    this.exitCode = exitCode;
  }
}

function blockedMain(paneId) {
  const agent = herdrJson("agent", "get", paneId)?.result?.agent;
  if (agent && !agent.name?.endsWith("-main")) throw new ReplyRefused(`pane ${paneId} is not a -main agent`, 2);
  return agent?.agent_status === "blocked" ? agent : null;
}

function herdrPane(...args) {
  const result = spawnSync(herdr, ["pane", ...args], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`herdr pane ${args[0]}: ${result.stderr.trim()}`);
}

async function reply(paneId, questionId, choice) {
  if (!/^[A-Za-z0-9]+:[A-Za-z0-9]+$/.test(paneId ?? "")) throw new ReplyRefused(`invalid pane: ${paneId}`, 2);
  if (!/^[0-9a-f]{16}$/.test(questionId ?? "")) throw new ReplyRefused(`invalid question: ${questionId}`, 2);
  if (!/^[1-9]$/.test(choice ?? "")) throw new ReplyRefused(`invalid option: ${choice}`, 2);
  const number = Number(choice);
  const waiting = blockedMain(paneId);
  if (!waiting) throw new ReplyRefused("Claude is no longer waiting for this answer", 3);
  const question = askedQuestion(paneScreen(paneId), waiting.state_change_seq);
  if (question?.id !== questionId || !Number.isInteger(waiting.state_change_seq)) {
    throw new ReplyRefused("the question on the Mac changed", 3);
  }
  if (!question.choices.some((option) => option.number === number))
    throw new ReplyRefused(`option ${number} cannot be answered from the iPhone`, 2);

  herdrPane("send-text", paneId, choice);
  await sleep(replySettleMs);
  if (question.preview) {
    const highlighted = askedQuestion(paneScreen(paneId), blockedMain(paneId)?.state_change_seq);
    if (highlighted?.id !== questionId || highlighted.options.find((option) => option.cursor)?.number !== number) {
      throw new Error("the answer was not taken, the option is not highlighted");
    }
    herdrPane("send-keys", paneId, "Enter");
    await sleep(replySettleMs);
  }

  const agent = blockedMain(paneId);
  if (!agent) return;
  const screen = paneScreen(paneId);
  const next = askedQuestion(screen, agent.state_change_seq);
  if (next?.id === questionId) throw new Error("the answer was not taken, the question is still on screen");
  if (!next) return;
  try {
    await notify(paneId, agent, screen);
  } catch (error) {
    console.error(`answer typed, next question not notified: ${error.message}`);
  }
}

async function deliver(device, key, headers, body) {
  const response = await postToApns(device, providerToken(key, device.team), headers, body);
  if (response.status === 200) return;
  if (response.status === 410 || /BadDeviceToken|Unregistered/.test(response.answer)) {
    rmSync(join(stateDir, "push-device.json"), { force: true });
    throw new Error(`APNs rejected the token (${response.status} ${response.answer}), device forgotten`);
  }
  throw new Error(`APNs ${response.status} ${response.answer}`);
}

function readJobFile(jobId, name) {
  try {
    return readFileSync(join(stateDir, "jobs", jobId, name), "utf8");
  } catch {
    return null;
  }
}

async function pushAnswer(jobId) {
  if (!/^[0-9]{14}-[0-9]+-[0-9a-f]{8}$/.test(jobId ?? "")) throw new Error(`invalid job: ${jobId}`);
  const answer = readJobFile(jobId, "answer");
  if (answer === null) throw new Error(`no answer for ${jobId}`);
  const device = readJson(join(stateDir, "push-device.json"));
  const key = apnsKey();
  if (!device || !key) throw new Error("no iPhone or no APNs key");

  const agent = readJobFile(jobId, "agent");
  const workspaceId = readJobFile(jobId, "workspace_id");
  const summary = answer.split("\n")[0].trim();
  const body = {
    aps: {
      alert: { title: readJobFile(jobId, "label") ?? workspaceId, subtitle: "Answer", body: shorten(summary) },
      sound: "default",
      "thread-id": agent,
    },
    kind: "answer",
    job_id: jobId,
    workspace_id: workspaceId,
    agent,
  };
  await deliver(device, key, { "apns-collapse-id": jobId }, body);
}

const [, , mode, ...args] = process.argv;
const run = mode === "answer" ? pushAnswer(args[0]) : mode === "reply" ? reply(...args) : main();
run.catch((error) => {
  console.error(mode === "reply" ? error.message : `heraldr notify: ${error.message}`);
  process.exit(error.exitCode ?? 1);
});
