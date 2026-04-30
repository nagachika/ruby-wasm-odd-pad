require 'js'
require 'web_component'

class MidiOutCtrl
  include WebComponent

  BRIDGE_OPT_VAL = "__bridge__"

  def connected_callback(element)
    @element = element
    element[:id] = "midi-out-group"
    element[:className] = "ctrl-group"

    build_dom
    setup_outputs
    listen_bridge_changes
  end

  private

  def build_dom
    doc = JS.global[:document]

    label = doc.call(:createElement, "label")
    label[:htmlFor] = "midi-out-select"
    label[:textContent] = "MIDI Out"

    @select = doc.call(:createElement, "select")
    @select[:id] = "midi-out-select"

    none_opt = doc.call(:createElement, "option")
    none_opt[:value] = ""
    none_opt[:textContent] = "– none –"
    @select.call(:appendChild, none_opt)

    @bridge_opt = doc.call(:createElement, "option")
    @bridge_opt[:value] = BRIDGE_OPT_VAL
    refresh_bridge_label
    @select.call(:appendChild, @bridge_opt)

    @status = doc.call(:createElement, "span")
    @status[:id] = "midi-out-status"

    @element.call(:appendChild, label)
    @element.call(:appendChild, @select)
    @element.call(:appendChild, @status)

    @select.call(:addEventListener, "change", proc { update_output })
  end

  def setup_outputs
    @access = JS.global[:App][:midiAccess]
    if @access.typeof.to_s == "undefined" || @access.nil?
      err = JS.global[:App][:midiAccessError]
      if err.typeof.to_s != "undefined" && !err.nil?
        @status[:textContent] = "unsupported (#{err[:message]})"
      else
        @status[:textContent] = "unsupported"
      end
      return
    end

    refresh_outputs
    @access[:onstatechange] = method(:refresh_outputs).to_proc
  end

  def refresh_outputs(*_args)
    doc = JS.global[:document]
    prev_id = @select[:value].to_s

    @select[:innerHTML] = ""
    none_opt = doc.call(:createElement, "option")
    none_opt[:value] = ""
    none_opt[:textContent] = "– none –"
    @select.call(:appendChild, none_opt)
    @select.call(:appendChild, @bridge_opt)

    output_ids = []
    @access[:outputs].call(:forEach, proc { |output, *|
      opt = doc.call(:createElement, "option")
      opt[:value] = output[:id]
      opt[:textContent] = output[:name]
      @select.call(:appendChild, opt)
      output_ids << output[:id].to_s
    })

    if !prev_id.empty? && (prev_id == BRIDGE_OPT_VAL || output_ids.include?(prev_id))
      @select[:value] = prev_id
    elsif !output_ids.empty?
      @select[:value] = output_ids.first
    end

    update_output
  end

  def update_output
    id = @select[:value].to_s
    app = JS.global[:App]
    if id == BRIDGE_OPT_VAL
      app[:_useBridge] = true
      app[:midiOutput] = JS.eval("return null")
      connected = app.call(:bridgeIsConnected).to_s == "true"
      @status[:textContent] = connected ? "connected" : "disconnected"
    elsif id.empty?
      app[:_useBridge] = false
      app[:midiOutput] = JS.eval("return null")
      @status[:textContent] = "(no port)"
    else
      app[:_useBridge] = false
      output = @access[:outputs].call(:get, id)
      app[:midiOutput] = output
      @status[:textContent] = output[:name]
    end
  end

  def refresh_bridge_label
    connected = JS.global[:App].call(:bridgeIsConnected).to_s == "true"
    @bridge_opt[:textContent] = connected ? "Wi-Fi Bridge ✓" : "Wi-Fi Bridge (disconnected)"
  end

  def listen_bridge_changes
    JS.global[:document].call(:addEventListener, "bridge-statechange", proc {
      refresh_bridge_label
      if @select[:value].to_s == BRIDGE_OPT_VAL
        connected = JS.global[:App].call(:bridgeIsConnected).to_s == "true"
        @status[:textContent] = connected ? "connected" : "disconnected"
      end
    })
  end

  MidiOutCtrl.register("midi-out-ctrl")
end
