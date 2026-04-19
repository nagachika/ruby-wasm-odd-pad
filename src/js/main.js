import { DefaultRubyVM } from "https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.8.1/dist/esm/browser.js";

const WASM_URL = "https://cdn.jsdelivr.net/npm/@ruby/3.3-wasm-wasi@2.8.1/dist/ruby+stdlib.wasm";

// ── Central App Object ────────────────────────────────────────────────────────
window.App = {
  vm: null,
  midiOutput: null,

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
    console.log(`[MIDI] status=0x${status.toString(16)} d1=${data1} d2=${data2} output=${this.midiOutput?.name ?? "null"}`);
    if (!this.midiOutput) { console.warn("[MIDI] No output port selected"); return; }
    this.midiOutput.send([status, data1, data2]);
  }
};

// ── UI Elements ───────────────────────────────────────────────────────────────
const startBtn   = document.getElementById("start-btn");
const loadingMsg = document.getElementById("loading-msg");
const overlay    = document.getElementById("start-overlay");

// ── MIDI Access (early request — desktop browsers often allow without gesture) ──
// On Android Chrome, this early request may not trigger a permission dialog
// (requires user activation), so setupMIDI() also falls back to a fresh
// request inside the Start-button click handler.
let _midiAccessPromise = null;
if (navigator.requestMIDIAccess) {
  try {
    _midiAccessPromise = navigator.requestMIDIAccess();
    _midiAccessPromise.catch(e => {
      console.warn("[MIDI] Early access request failed; will retry on click:", e);
      _midiAccessPromise = null;
    });
  } catch (e) {
    console.warn("[MIDI] Early access threw:", e);
    _midiAccessPromise = null;
  }
}

// ── Load WASM (start immediately, before button click) ────────────────────────
async function loadRubyVM() {
  const response = await fetch(WASM_URL);
  const buffer   = await response.arrayBuffer();
  const module   = await WebAssembly.compile(buffer);
  const { vm }   = await DefaultRubyVM(module);
  App.vm = vm;
  App.eval("require 'js'");
  startBtn.disabled    = false;
  startBtn.textContent = "Start";
  loadingMsg.textContent = "Ready — click to begin";
}

// ── Write Ruby source files into the WASM VFS ─────────────────────────────────
// Pattern copied verbatim from ruby-wasm-purified-synth/src/js/main.js
async function writeRubyFiles() {
  const files = [
    "src/ruby/web_component.rb",
    "src/ruby/midi_sender.rb",
    "src/ruby/pad_grid.rb",
    "src/ruby/main.rb",
  ];

  for (const file of files) {
    const res = await fetch(`${file}?_=${Date.now()}`);
    if (!res.ok) { console.error(`Failed to fetch ${file}`); continue; }
    const text = await res.text();

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

  if (!navigator.requestMIDIAccess) {
    statusEl.textContent = "unsupported";
    return;
  }

  let access = null;

  // 1) Try the early-request promise (works on desktop)
  if (_midiAccessPromise) {
    try { access = await _midiAccessPromise; } catch { access = null; }
  }

  // 2) Fallback: fresh request inside user gesture (required on Android Chrome)
  if (!access) {
    try {
      console.log("[MIDI] Requesting access inside click handler (user gesture)…");
      access = await navigator.requestMIDIAccess();
    } catch (e) {
      console.error("[MIDI] Access failed:", e);
      statusEl.textContent = "denied";
      return;
    }
  }
  console.log("[MIDI] Access granted, inputs:", access.inputs.size, "outputs:", access.outputs.size);

  function refreshOutputs() {
    const outputs = [...access.outputs.values()];
    console.log("[MIDI] outputs found:", outputs.length, outputs.map(o => `${o.name}(${o.id})`));

    // Rebuild <select> options
    const prevId = selectEl.value;
    selectEl.innerHTML = '<option value="">– none –</option>';
    outputs.forEach(o => {
      const opt = document.createElement("option");
      opt.value = o.id;
      opt.textContent = o.name;
      selectEl.appendChild(opt);
    });
    // Restore previous selection, or auto-select first port
    if (prevId && [...selectEl.options].some(o => o.value === prevId)) {
      selectEl.value = prevId;
    } else if (outputs.length > 0) {
      selectEl.value = outputs[0].id;
    }
    updateOutput();
  }

  function updateOutput() {
    const id = selectEl.value;
    App.midiOutput = id ? access.outputs.get(id) ?? null : null;
    console.log("[MIDI] midiOutput set to:", App.midiOutput?.name ?? "null");
    statusEl.textContent = App.midiOutput ? App.midiOutput.name : "(no port)";
  }

  selectEl.addEventListener("change", updateOutput);
  access.onstatechange = refreshOutputs;
  refreshOutputs();
}

// ── Wire Header Controls → MIDI CC ────────────────────────────────────────────
function wireControls() {
  const octaveSlider = document.getElementById("ctrl-octave");
  const octaveVal    = document.getElementById("ctrl-octave-val");
  octaveSlider.addEventListener("input", () => {
    const v = parseInt(octaveSlider.value);
    const delta = v - 64;
    octaveVal.textContent = delta > 0 ? `+${delta}` : delta === 0 ? "±0" : `${delta}`;
    App.eval(`$midi_sender.send_cc(23, #{v})`.replace("#{v}", v));
  });

  document.getElementById("ctrl-root").addEventListener("change", e => {
    App.eval(`$midi_sender.send_cc(22, ${e.target.value})`);
  });

  document.getElementById("ctrl-dim").addEventListener("change", e => {
    App.eval(`$midi_sender.send_cc(20, ${e.target.value})`);
  });

  document.getElementById("ctrl-preset").addEventListener("change", e => {
    App.eval(`$midi_sender.send_cc(21, ${e.target.value})`);
  });

  document.getElementById("ctrl-volume").addEventListener("input", e => {
    App.eval(`$midi_sender.send_cc(7, ${e.target.value})`);
  });
}

// ── Boot Sequence ─────────────────────────────────────────────────────────────
startBtn.addEventListener("click", async () => {
  // CRITICAL: request MIDI access SYNCHRONOUSLY at the top of the click handler.
  // On Android Chrome, user activation is consumed by the first await, so
  // requestMIDIAccess() must be invoked before any await to be recognised as
  // a user-gesture call.  We store the promise and consume it inside setupMIDI.
  if (navigator.requestMIDIAccess) {
    const freshReq = navigator.requestMIDIAccess();
    freshReq.catch(e => console.warn("[MIDI] fresh request rejected:", e));
    _midiAccessPromise = freshReq;
  }

  startBtn.disabled    = true;
  startBtn.textContent = "Initializing…";

  await setupMIDI();
  await writeRubyFiles();

  // Boot Ruby side — PadGrid.register("pad-grid") is called inside main.rb
  // but no <pad-grid> element is in the DOM yet, so connectedCallback won't fire
  // (avoids Ruby VM re-entrancy)
  App.eval("require 'main'");

  // Now that the custom element is defined, add it to the DOM.
  // connectedCallback fires here, safely outside any App.eval() call.
  const padGrid = document.createElement("pad-grid");
  document.getElementById("grid-container").appendChild(padGrid);

  wireControls();
  overlay.style.display = "none";

  console.log("Odd Pad ready.");
});

// Start loading WASM immediately
loadRubyVM();
