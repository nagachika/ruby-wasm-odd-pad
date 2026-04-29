import { DefaultRubyVM } from "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.8.1/dist/esm/browser.js";

const WASM_URL        = "https://cdn.jsdelivr.net/npm/@ruby/3.3-wasm-wasi@2.8.1/dist/ruby+stdlib.wasm";
const BRIDGE_OPT_VAL   = "__bridge__";
const BRIDGE_HOST_KEY  = "odd-pad.bridge-hostport";
const BRIDGE_RETRY_MS  = 3000;
const DEBUG            = new URLSearchParams(location.search).has("debug");

function hostPortToWss(hostPort) {
  return hostPort ? `wss://${hostPort}` : "";
}

// ── WebSocket Bridge ──────────────────────────────────────────────────────────

let bridgeWs        = null;
let bridgeConnected = false;
let bridgeRetryTimer = null;

function connectBridge(url) {
  clearTimeout(bridgeRetryTimer);
  if (bridgeWs) { bridgeWs.onclose = null; bridgeWs.close(); bridgeWs = null; }
  if (!url) { bridgeConnected = false; refreshBridgeOption(); return; }

  console.log("[Bridge] Connecting to", url);
  try {
    bridgeWs = new WebSocket(url);
  } catch (e) {
    console.warn("[Bridge] Invalid URL:", e.message);
    bridgeConnected = false;
    refreshBridgeOption();
    return;
  }

  bridgeWs.onopen = () => {
    console.log("[Bridge] Connected:", url);
    bridgeConnected = true;
    refreshBridgeOption();
  };

  bridgeWs.onclose = () => {
    console.log("[Bridge] Disconnected, retrying in", BRIDGE_RETRY_MS, "ms");
    bridgeWs = null;
    bridgeConnected = false;
    refreshBridgeOption();
    const savedHostPort = localStorage.getItem(BRIDGE_HOST_KEY) ?? "";
    if (hostPortToWss(savedHostPort) === url) {
      bridgeRetryTimer = setTimeout(() => connectBridge(url), BRIDGE_RETRY_MS);
    }
  };

  bridgeWs.onerror = e => console.warn("[Bridge] Error:", e);
}

function sendViaBridge(status, data1, data2) {
  if (!bridgeWs || bridgeWs.readyState !== WebSocket.OPEN) {
    console.warn("[Bridge] sendMidi: not connected");
    return;
  }
  bridgeWs.send(JSON.stringify([status, data1, data2]));
}

// Updated by setupMIDI once the dropdown exists
let refreshBridgeOption = () => {};

// ── Central App Object ────────────────────────────────────────────────────────

window.App = {
  vm:         null,
  midiOutput: null,
  _useBridge: false,

  eval(code, ctx = "Main") {
    try {
      return this.vm.eval(code);
    } catch (e) {
      console.error(`[Ruby Error in ${ctx}]:`, e);
      if (e.stack) console.error(e.stack);
      return null;
    }
  },

  sendMidi(status, data1, data2) {
    if (DEBUG) console.log(`[MIDI] 0x${status.toString(16).toUpperCase()} ${data1} ${data2}`);
    if (this._useBridge) {
      sendViaBridge(status, data1, data2);
    } else if (this.midiOutput) {
      this.midiOutput.send([status, data1, data2]);
    } else {
      console.warn("[MIDI] No output selected");
    }
  },

  bridgeIsConnected() { return bridgeConnected; },
  bridgeHostPort()    { return localStorage.getItem(BRIDGE_HOST_KEY) ?? ""; },
  applyBridge(hostPort) {
    localStorage.setItem(BRIDGE_HOST_KEY, hostPort);
    connectBridge(hostPortToWss(hostPort));
  },
};

// ── UI Elements ───────────────────────────────────────────────────────────────

const startBtn   = document.getElementById("start-btn");
const loadingMsg = document.getElementById("loading-msg");
const overlay    = document.getElementById("start-overlay");

// ── Bridge: connect on load with saved host:port ──────────────────────────────

{
  const savedHostPort = localStorage.getItem(BRIDGE_HOST_KEY) ?? "";
  if (savedHostPort) connectBridge(hostPortToWss(savedHostPort));
}

// ── MIDI Access (early request) ───────────────────────────────────────────────

let _midiAccessPromise = null;
window.__midiErr = null;

if (typeof navigator.requestMIDIAccess !== "function") {
  window.__midiErr = {
    name: "Unsupported",
    message: `requestMIDIAccess is ${navigator.requestMIDIAccess === undefined ? "undefined" : "null"} (insecure context?)`
  };
} else {
  try {
    _midiAccessPromise = navigator.requestMIDIAccess();
    _midiAccessPromise.catch(e => {
      console.warn("[MIDI] Early access request failed; will retry on click:", e);
      window.__midiErr = { name: e.name || "Error", message: e.message || String(e) };
      _midiAccessPromise = null;
    });
  } catch (e) {
    console.warn("[MIDI] Early access threw:", e);
    window.__midiErr = { name: e.name || "Error", message: e.message || String(e) };
    _midiAccessPromise = null;
  }
}

// ── Load WASM ─────────────────────────────────────────────────────────────────

async function loadRubyVM() {
  const response = await fetch(WASM_URL);
  const buffer   = await response.arrayBuffer();
  const module   = await WebAssembly.compile(buffer);
  const { vm }   = await DefaultRubyVM(module);
  App.vm = vm;
  App.eval("require 'js'");
  startBtn.disabled      = false;
  startBtn.textContent   = "Start";
  loadingMsg.textContent = "Ready — click to begin";
}

// ── Write Ruby source files into WASM VFS ────────────────────────────────────

async function writeRubyFiles() {
  const files = [
    "src/ruby/web_component.rb",
    "src/ruby/midi_sender.rb",
    "src/ruby/pad_grid.rb",
    "src/ruby/main.rb",
    "src/ruby/ctrl_group.rb",
    "src/ruby/kebab_menu.rb",
  ];

  const bust = Date.now();
  const fetched = await Promise.all(
    files.map(async file => {
      const res = await fetch(`${file}?_=${bust}`);
      if (!res.ok) { console.error(`Failed to fetch ${file}`); return { file, text: null }; }
      return { file, text: await res.text() };
    })
  );

  for (const { file, text } of fetched) {
    if (text === null) continue;

    window._rubyFileContent = text;
    const vfsPath = `/${file}`;
    const dir = vfsPath.substring(0, vfsPath.lastIndexOf("/"));

    if (dir) {
      window._tempDir = dir;
      App.eval(`
        parts = JS.global[:_tempDir].to_s.split('/').reject(&:empty?)
        current = ''
        parts.each do |part|
          current = current + '/' + part
          Dir.mkdir(current) unless Dir.exist?(current)
        end
      `, "DirSetup");
      delete window._tempDir;
    }

    window._tempPath = vfsPath;
    App.eval(`File.write(JS.global[:_tempPath].to_s, JS.global[:_rubyFileContent])`, "FileWrite");
    delete window._tempPath;
    console.log(`Loaded ${file}`);
  }

  delete window._rubyFileContent;
  App.eval("$LOAD_PATH.unshift '/src/ruby'");
}

// ── MIDI Setup ────────────────────────────────────────────────────────────────

async function setupMIDI() {
  const selectEl = document.getElementById("midi-out-select");
  const statusEl = document.getElementById("midi-out-status");

  // Inject "Wi-Fi Bridge" as the first option and wire refreshBridgeOption
  const bridgeOpt = document.createElement("option");
  bridgeOpt.value = BRIDGE_OPT_VAL;
  selectEl.appendChild(bridgeOpt);

  refreshBridgeOption = () => {
    bridgeOpt.textContent = bridgeConnected ? "Wi-Fi Bridge ✓" : "Wi-Fi Bridge (disconnected)";
    if (selectEl.value === BRIDGE_OPT_VAL) {
      statusEl.textContent = bridgeConnected ? "connected" : "disconnected";
    }
  };
  refreshBridgeOption();

  const showErr = (label, e) => {
    const msg = e?.message || String(e);
    statusEl.textContent = `${label}: ${msg}`;
    console.error(`[MIDI] ${label}:`, e);
  };

  if (typeof navigator.requestMIDIAccess !== "function") {
    statusEl.textContent = window.__midiErr
      ? `unsupported (${window.__midiErr.message})`
      : "unsupported";
    return;
  }

  let access = null;
  let lastErr = null;

  if (_midiAccessPromise) {
    try { access = await _midiAccessPromise; } catch (e) { lastErr = e; access = null; }
  } else if (window.__midiErr) {
    lastErr = window.__midiErr;
  }

  if (!access) {
    try {
      console.log("[MIDI] Requesting access inside click handler (user gesture)…");
      access = await navigator.requestMIDIAccess();
    } catch (e) {
      showErr("Access failed", e || lastErr);
      return;
    }
  }
  console.log("[MIDI] Access granted, outputs:", access.outputs.size);

  function refreshOutputs() {
    const outputs = [...access.outputs.values()];
    const prevId  = selectEl.value;

    // Rebuild keeping bridge option at top
    selectEl.innerHTML = '<option value="">– none –</option>';
    selectEl.appendChild(bridgeOpt);
    outputs.forEach(o => {
      const opt = document.createElement("option");
      opt.value       = o.id;
      opt.textContent = o.name;
      selectEl.appendChild(opt);
    });

    if (prevId && [...selectEl.options].some(o => o.value === prevId)) {
      selectEl.value = prevId;
    } else if (outputs.length > 0) {
      selectEl.value = outputs[0].id;
    }
    updateOutput();
  }

  function updateOutput() {
    const id = selectEl.value;
    if (id === BRIDGE_OPT_VAL) {
      App._useBridge  = true;
      App.midiOutput  = null;
      statusEl.textContent = bridgeConnected ? "connected" : "disconnected";
    } else {
      App._useBridge  = false;
      App.midiOutput  = id ? access.outputs.get(id) ?? null : null;
      statusEl.textContent = App.midiOutput ? App.midiOutput.name : "(no port)";
    }
  }

  selectEl.addEventListener("change", updateOutput);
  access.onstatechange = refreshOutputs;
  refreshOutputs();
}

// ── Boot Sequence ─────────────────────────────────────────────────────────────

startBtn.addEventListener("click", async () => {
  startBtn.disabled    = true;
  startBtn.textContent = "Initializing…";

  await setupMIDI();
  await writeRubyFiles();

  App.eval("require 'main'");

  const midiOutGroup = document.getElementById("midi-out-group");
  midiOutGroup.before(document.createElement("dim-ctrl"), document.createElement("vol-ctrl"));

  document.querySelector("header").appendChild(document.createElement("kebab-menu"));

  const padGrid = document.createElement("pad-grid");
  document.getElementById("grid-container").appendChild(padGrid);
  document.addEventListener("contextmenu", e => e.preventDefault());
  overlay.style.display = "none";

  console.log("Odd Pad ready.");
});

// Start loading WASM immediately
loadRubyVM();
