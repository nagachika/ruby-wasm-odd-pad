#!/usr/bin/env ruby
# tool/midi_bridge.rb
# WebSocket → MIDI bridge for odd-pad.
# Receives MIDI messages from the Android browser over WSS and forwards
# them to a CoreMIDI output port (IAC Driver or hardware) on macOS.
#
# Usage:
#   bundle exec ruby midi_bridge.rb [PORT_NUMBER]
#
# PORT_NUMBER: index of the MIDI output port to use (shown at startup).
#              Omit to be prompted interactively.

require "bundler/setup"
require "em-websocket"
require "unimidi"
require "openssl"
require "json"

BRIDGE_PORT = 8765
CERT_DIR    = File.expand_path("../../.certs", __FILE__)
CERT_PATH   = File.join(CERT_DIR, "server.crt")
KEY_PATH    = File.join(CERT_DIR, "server.key")

# ── TLS context ────────────────────────────────────────────────────────────────

def build_tls_opts
  unless File.exist?(CERT_PATH) && File.exist?(KEY_PATH)
    warn <<~MSG
      [bridge] TLS certificate not found in #{CERT_DIR}/
      Run `rake https` once from the project root to generate it,
      then re-run this script.
    MSG
    exit 1
  end
  { private_key_file: KEY_PATH, cert_chain_file: CERT_PATH }
end

# ── MIDI port selection ────────────────────────────────────────────────────────

def select_midi_output(port_arg)
  outputs = UniMIDI::Output.all
  if outputs.empty?
    warn <<~MSG
      [bridge] No MIDI output ports found.
      On macOS, open "Audio MIDI Setup", double-click "IAC Driver",
      check "Device is online", and add a Bus if none exists.
    MSG
    exit 1
  end

  puts "[bridge] Available MIDI outputs:"
  outputs.each_with_index { |o, i| puts "  #{i}: #{o.name}" }

  index = if port_arg
    port_arg.to_i
  else
    print "Select port number [0]: "
    input = $stdin.gets.strip
    input.empty? ? 0 : input.to_i
  end

  unless (0...outputs.size).include?(index)
    warn "[bridge] Invalid port index: #{index}"
    exit 1
  end

  output = outputs[index]
  output.open
  puts "[bridge] Using MIDI output: #{output.name}"
  output
end

# ── Local IP hint ───────────────────────────────────────────────────────────────

def local_ip_hint
  require "socket"
  addrs = Socket.ip_address_list.select { |a| a.ipv4? && !a.ipv4_loopback? }
  addrs.map { |a| "  wss://#{a.ip_address}:#{BRIDGE_PORT}" }.join("\n")
rescue
  ""
end

# ── Main ───────────────────────────────────────────────────────────────────────

port_arg = ARGV[0]
midi_out = select_midi_output(port_arg)
tls_opts = build_tls_opts

puts <<~MSG

  [bridge] Starting WSS server on port #{BRIDGE_PORT}
  [bridge] Connect from odd-pad using one of:
    wss://naumanica.local:#{BRIDGE_PORT}
#{local_ip_hint}
  [bridge] Press Ctrl+C to stop.

MSG

clients = 0

EM.run do
  EM::WebSocket.run(host: "0.0.0.0", port: BRIDGE_PORT, secure: true, tls_options: tls_opts) do |ws|
    ws.onopen do |handshake|
      clients += 1
      puts "[bridge] Client connected: #{handshake.origin}  (total: #{clients})"
    end

    ws.onmessage do |raw|
      bytes = JSON.parse(raw)
      next unless bytes.is_a?(Array) && bytes.size >= 3
      status, d1, d2 = bytes.map(&:to_i)
      midi_out.puts(status, d1, d2)
      puts "[bridge] MIDI  0x#{status.to_s(16).upcase} #{d1} #{d2}"
    rescue JSON::ParserError => e
      warn "[bridge] Bad message: #{e.message}"
    end

    ws.onclose do
      clients -= 1
      puts "[bridge] Client disconnected  (total: #{clients})"
    end

    ws.onerror do |e|
      warn "[bridge] WebSocket error: #{e.message}"
    end
  end

  trap("INT") do
    puts "\n[bridge] Shutting down…"
    midi_out.close rescue nil
    EM.stop
  end
end
