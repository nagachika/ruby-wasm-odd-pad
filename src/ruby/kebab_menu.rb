require 'js'
require 'web_component'

class KebabMenu
  include WebComponent

  CSS = <<~CSS
    :host {
      position: relative;
    }

    #btn {
      background: none;
      border: none;
      color: #888;
      font-size: 1.3rem;
      line-height: 1;
      padding: 4px 8px;
      border-radius: 4px;
      cursor: pointer;
      touch-action: auto;
    }
    #btn:hover { background: #333; color: #eee; }

    #dropdown {
      position: absolute;
      right: 0;
      top: calc(100% + 4px);
      background: #2a2a2a;
      border: 1px solid #444;
      border-radius: 6px;
      min-width: 170px;
      z-index: 50;
      padding: 4px 0;
      box-shadow: 0 4px 12px rgba(0,0,0,0.5);
    }
    #dropdown[hidden] { display: none; }

    .item {
      display: block;
      width: 100%;
      background: none;
      border: none;
      color: #ddd;
      text-align: left;
      padding: 10px 16px;
      cursor: pointer;
      font-size: 0.85rem;
      touch-action: auto;
    }
    .item:hover { background: #383838; color: #fff; }

    dialog {
      background: #242424;
      color: #eee;
      border: 1px solid #555;
      border-radius: 10px;
      padding: 24px 20px 16px;
      min-width: 300px;
      touch-action: auto;
    }
    dialog::backdrop { background: rgba(0, 0, 0, 0.65); }

    dialog h2 {
      margin: 0 0 16px;
      font-size: 1rem;
      font-weight: 600;
    }

    .input-row {
      display: flex;
      align-items: center;
      gap: 6px;
      margin-bottom: 6px;
    }

    .input-prefix {
      font-size: 0.82rem;
      color: #888;
      white-space: nowrap;
    }

    #hostport {
      flex: 1;
      background: #333;
      color: #eee;
      border: 1px solid #555;
      border-radius: 4px;
      padding: 6px 8px;
      font-size: 0.85rem;
      user-select: text;
      -webkit-user-select: text;
      touch-action: auto;
    }

    .status-hint {
      font-size: 0.75rem;
      color: #666;
      margin-bottom: 18px;
      min-height: 1em;
    }
    .status-hint.ok  { color: #69db7c; }
    .status-hint.err { color: #f44; }

    .dialog-btns {
      display: flex;
      justify-content: flex-end;
      gap: 8px;
    }
    .dialog-btns button {
      padding: 7px 18px;
      border-radius: 6px;
      border: 1px solid #555;
      font-size: 0.85rem;
      cursor: pointer;
      touch-action: auto;
    }
    .btn-cancel { background: #333; color: #ccc; }
    .btn-ok     { background: #0070f3; color: #fff; border-color: #0070f3; }
  CSS

  def connected_callback(element)
    @shadow = element.call(:attachShadow, JS.eval("return { mode: 'open' }"))
    @dropdown_visible = false

    inject_style
    build_button
    build_dropdown
    build_dialog
    attach_events
  end

  private

  def inject_style
    style = JS.global[:document].call(:createElement, "style")
    style[:textContent] = CSS
    @shadow.call(:appendChild, style)
  end

  def build_button
    @btn = JS.global[:document].call(:createElement, "button")
    @btn[:id] = "btn"
    @btn[:ariaLabel] = "設定メニュー"
    @btn[:textContent] = "⋮"
    @shadow.call(:appendChild, @btn)
  end

  def build_dropdown
    doc = JS.global[:document]
    @dropdown = doc.call(:createElement, "div")
    @dropdown[:id] = "dropdown"
    @dropdown[:hidden] = true

    @item_bridge = doc.call(:createElement, "button")
    @item_bridge[:className] = "item"
    @item_bridge[:textContent] = "Bridge URL を設定…"
    @dropdown.call(:appendChild, @item_bridge)

    @shadow.call(:appendChild, @dropdown)
  end

  def build_dialog
    doc = JS.global[:document]
    @dialog = doc.call(:createElement, "dialog")

    h2 = doc.call(:createElement, "h2")
    h2[:textContent] = "Bridge URL"

    input_row = doc.call(:createElement, "div")
    input_row[:className] = "input-row"
    prefix = doc.call(:createElement, "span")
    prefix[:className] = "input-prefix"
    prefix[:textContent] = "wss://"
    @hostport_input = doc.call(:createElement, "input")
    @hostport_input[:id] = "hostport"
    @hostport_input[:type] = "text"
    @hostport_input[:placeholder] = "host:8765"
    @hostport_input[:autocomplete] = "off"
    @hostport_input[:spellcheck] = false
    input_row.call(:appendChild, prefix)
    input_row.call(:appendChild, @hostport_input)

    @status_hint = doc.call(:createElement, "p")
    @status_hint[:className] = "status-hint"

    btns = doc.call(:createElement, "div")
    btns[:className] = "dialog-btns"
    @cancel_btn = doc.call(:createElement, "button")
    @cancel_btn[:className] = "btn-cancel"
    @cancel_btn[:textContent] = "キャンセル"
    @ok_btn = doc.call(:createElement, "button")
    @ok_btn[:className] = "btn-ok"
    @ok_btn[:textContent] = "OK"
    btns.call(:appendChild, @cancel_btn)
    btns.call(:appendChild, @ok_btn)

    @dialog.call(:appendChild, h2)
    @dialog.call(:appendChild, input_row)
    @dialog.call(:appendChild, @status_hint)
    @dialog.call(:appendChild, btns)

    @shadow.call(:appendChild, @dialog)
  end

  def attach_events
    @btn.call(:addEventListener, "click", proc { |e|
      e.call(:stopPropagation)
      @dropdown_visible = !@dropdown_visible
      @dropdown[:hidden] = !@dropdown_visible
    })

    JS.global[:document].call(:addEventListener, "click", proc {
      @dropdown_visible = false
      @dropdown[:hidden] = true
    })

    @item_bridge.call(:addEventListener, "click", proc {
      @dropdown_visible = false
      @dropdown[:hidden] = true

      connected = JS.global[:App].call(:bridgeIsConnected).to_s == "true"
      host_port = JS.global[:App].call(:bridgeHostPort).to_s
      @hostport_input[:value] = host_port
      if connected
        @status_hint[:textContent] = "現在: 接続中"
        @status_hint[:className] = "status-hint ok"
      elsif !host_port.empty?
        @status_hint[:textContent] = "現在: 未接続"
        @status_hint[:className] = "status-hint err"
      else
        @status_hint[:textContent] = ""
        @status_hint[:className] = "status-hint"
      end

      @dialog.call(:showModal)
      JS.global.call(:setTimeout, proc { @hostport_input.call(:focus) }, 50)
    })

    @cancel_btn.call(:addEventListener, "click", proc { @dialog.call(:close) })

    @ok_btn.call(:addEventListener, "click", proc {
      host_port = @hostport_input[:value].to_s.strip
      JS.global[:App].call(:applyBridge, host_port)
      @dialog.call(:close)
    })

    @hostport_input.call(:addEventListener, "keydown", proc { |e|
      @ok_btn.call(:click) if e[:key].to_s == "Enter"
    })
  end

  KebabMenu.register("kebab-menu")
end
