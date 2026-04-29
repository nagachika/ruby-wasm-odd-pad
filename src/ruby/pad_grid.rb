require 'js'
require 'web_component'

# 5x5 viewport into the 9x9 MIDI grid (centre region: x=2..6, y=2..6).
# Note number formula: NoteNumber = 36 + (y * 9) + x
# Centre tonic: (4,4) = MIDI note 76
class PadGrid
  include WebComponent

  VIEW_XS   = (2..6).to_a   # left-to-right columns
  VIEW_YS   = (2..6).to_a   # bottom-to-top rows (rendered top-to-bottom in DOM)
  CENTER_X  = 4
  CENTER_Y  = 4

  PX_PER_OCTAVE = 40
  MAX_OCTAVE    = 3
  OCTAVE_CC     = 23
  OCTAVE_CENTER = 64

  PAD_CSS = <<~CSS
    :host {
      display: block;
      touch-action: none;
      user-select: none;
      -webkit-user-select: none;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(5, 1fr);
      gap: 5px;
      width: 100%;
      aspect-ratio: 1 / 1;
      touch-action: none;
    }
    .pad {
      background: #2d4a6e;
      border: none;
      border-radius: 6px;
      cursor: pointer;
      touch-action: none;
      aspect-ratio: 1 / 1;
      min-width: 0;
      display: flex;
      align-items: center;
      justify-content: center;
      color: rgba(255, 255, 255, 0.35);
      font-size: clamp(0.5rem, 2vw, 0.75rem);
      font-family: monospace;
      transition: background 0.05s;
    }
    .pad.root          { background: #1a5c3a; }
    .pad.active        { background: #4dabf7; color: #fff; font-size: clamp(0.7rem, 2.6vw, 1rem); }
    .pad.root.active   { background: #69db7c; color: #fff; }
    .debug-overlay {
      position: fixed;
      bottom: 0;
      left: 0;
      right: 0;
      background: rgba(0, 0, 0, 0.85);
      color: #0f0;
      font-family: monospace;
      font-size: 11px;
      padding: 6px 10px;
      max-height: 30vh;
      overflow-y: auto;
      z-index: 999;
      pointer-events: none;
    }
    .debug-overlay .cancel { color: #f44; }
    .debug-overlay .info   { color: #4dabf7; }
  CSS

  def connected_callback(js_element)
    @element = js_element
    @shadow  = @element.call(:attachShadow, JS.eval("return { mode: 'open' }"))
    @pointers = {}
    @debug = JS.global[:location][:search].to_s.include?("debug=1")
    inject_style
    render_grid
    attach_events
    setup_debug_overlay if @debug
  end

  private

  def note_number(x, y)
    36 + (y * 9) + x
  end

  def inject_style
    style = JS.global[:document].call(:createElement, "style")
    style[:textContent] = PAD_CSS
    @shadow.call(:appendChild, style)
  end

  def render_grid
    doc   = JS.global[:document]
    @grid = doc.call(:createElement, "div")
    @grid[:className] = "grid"

    # Render rows high-to-low (y=6 at top, y=2 at bottom) — musical convention
    VIEW_YS.reverse_each do |y|
      VIEW_XS.each do |x|
        note = note_number(x, y)
        btn  = doc.call(:createElement, "button")
        css  = (x == CENTER_X && y == CENTER_Y) ? "pad root" : "pad"
        btn[:className]       = css
        btn[:dataset][:note]  = note
        btn[:dataset][:x]     = x
        btn[:dataset][:y]     = y
        btn[:textContent]     = note.to_s
        @grid.call(:appendChild, btn)
      end
    end

    @shadow.call(:appendChild, @grid)
  end

  def attach_events
    # Touch Events: primary handler for finger input on Android.
    # preventDefault() in touchstart stops the browser from also firing Pointer Events
    # for touch contacts, avoiding the OS-level gesture cancellation that plagues
    # Pointer Events on 3+ simultaneous touches.
    opts = JS.eval("return { passive: false }")
    on_tstart  = method(:on_touchstart).to_proc
    on_tmove   = method(:on_touchmove).to_proc
    on_tend    = method(:on_touchend).to_proc
    on_tcancel = method(:on_touchcancel).to_proc
    @grid.call(:addEventListener, "touchstart",  on_tstart,  opts)
    @grid.call(:addEventListener, "touchmove",   on_tmove,   opts)
    @grid.call(:addEventListener, "touchend",    on_tend)
    @grid.call(:addEventListener, "touchcancel", on_tcancel)

    # Pointer Events: mouse-only fallback for desktop testing.
    # Guards in each handler skip non-mouse pointers.
    on_pdown   = method(:on_pointerdown).to_proc
    on_pmove   = method(:on_pointermove).to_proc
    on_pup     = method(:on_pointerup).to_proc
    on_pcancel = method(:on_pointercancel).to_proc
    on_lost    = method(:on_lostpointercapture).to_proc
    @grid.call(:addEventListener, "pointerdown",        on_pdown)
    @grid.call(:addEventListener, "pointermove",         on_pmove)
    @grid.call(:addEventListener, "pointerup",           on_pup)
    @grid.call(:addEventListener, "pointercancel",       on_pcancel)
    @grid.call(:addEventListener, "lostpointercapture",  on_lost)
  end

  # ── Touch Event handlers ───────────────────────────────────────────────────

  def on_touchstart(event)
    event.call(:preventDefault)
    each_changed_touch(event) do |touch|
      target   = touch[:target]
      note_val = target[:dataset][:note]
      next if note_val.typeof == "undefined" || note_val.to_s.empty?

      id       = touch[:identifier].to_i
      note     = note_val.to_i
      velocity = calc_touch_velocity(touch, target)

      @pointers[id] = { target: target, note: note, start_y: touch[:clientY].to_f, offset: 0 }
      target[:classList].call(:add, "active")
      target[:textContent] = "±0"
      $midi_sender.note_on(note, velocity)
      $midi_sender.send_cc(OCTAVE_CC, OCTAVE_CENTER) if @pointers.size == 1
      log_debug("touchstart", id, note)
    end
  end

  def on_touchmove(event)
    event.call(:preventDefault)
    each_changed_touch(event) do |touch|
      id    = touch[:identifier].to_i
      state = @pointers[id]
      next unless state

      dy         = state[:start_y] - touch[:clientY].to_f
      new_offset = (dy / PX_PER_OCTAVE).to_i.clamp(-MAX_OCTAVE, MAX_OCTAVE)
      next if new_offset == state[:offset]

      state[:offset] = new_offset
      state[:target][:textContent] = format_offset(new_offset)
      $midi_sender.send_cc(OCTAVE_CC, OCTAVE_CENTER + new_offset)
    end
  end

  def on_touchend(event)
    each_changed_touch(event) do |touch|
      id    = touch[:identifier].to_i
      state = @pointers.delete(id)
      next unless state
      release_pad(state)
      log_debug("touchend", id, state[:note])
    end
  end

  def on_touchcancel(event)
    each_changed_touch(event) do |touch|
      id = touch[:identifier].to_i
      log_debug("touchcancel-raw", id)
      state = @pointers.delete(id)
      next unless state
      release_pad(state)
      log_debug("touchcancel", id, state[:note])
    end
  end

  # ── Pointer Event handlers (mouse only) ───────────────────────────────────

  def on_pointerdown(event)
    return unless event[:pointerType].to_s == "mouse"
    target   = event[:target]
    note_val = target[:dataset][:note]
    return if note_val.typeof == "undefined" || note_val.to_s.empty?

    event.call(:preventDefault)
    pointer_id = event[:pointerId].to_i
    @grid.call(:setPointerCapture, event[:pointerId])

    note     = note_val.to_i
    velocity = calc_velocity(event, target)

    @pointers[pointer_id] = { target: target, note: note, start_y: event[:clientY].to_f, offset: 0 }
    target[:classList].call(:add, "active")
    target[:textContent] = "±0"
    $midi_sender.note_on(note, velocity)
    $midi_sender.send_cc(OCTAVE_CC, OCTAVE_CENTER) if @pointers.size == 1
    log_debug("mousedown", pointer_id, note)
  end

  def on_pointermove(event)
    return unless event[:pointerType].to_s == "mouse"
    pointer_id = event[:pointerId].to_i
    state      = @pointers[pointer_id]
    return unless state

    dy         = state[:start_y] - event[:clientY].to_f
    new_offset = (dy / PX_PER_OCTAVE).to_i.clamp(-MAX_OCTAVE, MAX_OCTAVE)
    return if new_offset == state[:offset]

    state[:offset] = new_offset
    state[:target][:textContent] = format_offset(new_offset)
    $midi_sender.send_cc(OCTAVE_CC, OCTAVE_CENTER + new_offset)
  end

  def on_pointerup(event)
    return unless event[:pointerType].to_s == "mouse"
    pointer_id = event[:pointerId].to_i
    state      = @pointers.delete(pointer_id)
    return unless state
    release_pad(state)
    log_debug("mouseup", pointer_id, state[:note])
  end

  def on_pointercancel(event)
    cleanup_mouse_pointer(event, "pointercancel")
  end

  def on_lostpointercapture(event)
    cleanup_mouse_pointer(event, "lostpointercapture")
  end

  # ── Shared helpers ─────────────────────────────────────────────────────────

  def cleanup_mouse_pointer(event, label)
    return unless event[:pointerType].to_s == "mouse"
    pointer_id = event[:pointerId].to_i
    log_debug("#{label}-raw(mouse)", pointer_id)
    state = @pointers.delete(pointer_id)
    return unless state
    release_pad(state)
    log_debug("#{label}(mouse)", pointer_id, state[:note])
  end

  def each_changed_touch(event)
    changed = event[:changedTouches]
    changed[:length].to_i.times { |i| yield changed.call(:item, i) }
  end

  def release_pad(state)
    state[:target][:classList].call(:remove, "active")
    state[:target][:textContent] = state[:note].to_s
    $midi_sender.note_off(state[:note])
  end

  def format_offset(n)
    n > 0 ? "+#{n}" : (n == 0 ? "±0" : n.to_s)
  end

  def calc_touch_velocity(touch, target)
    radius = touch[:radiusX].to_f
    if radius > 1
      (radius * 2 / 50.0 * 127).round.clamp(1, 127)
    else
      rect  = target.call(:getBoundingClientRect)
      rel_y = 1.0 - (touch[:clientY].to_f - rect[:top].to_f) / rect[:height].to_f
      (rel_y * 100 + 27).round.clamp(1, 127)
    end
  end

  def calc_velocity(event, target)
    width = event[:width].to_f
    if width > 1
      (width / 50.0 * 127).round.clamp(1, 127)
    else
      rect  = target.call(:getBoundingClientRect)
      rel_y = 1.0 - (event[:clientY].to_f - rect[:top].to_f) / rect[:height].to_f
      (rel_y * 100 + 27).round.clamp(1, 127)
    end
  end

  # ── Debug overlay (enabled with ?debug=1) ─────────────────────────────────

  def setup_debug_overlay
    doc = JS.global[:document]
    @debug_el = doc.call(:createElement, "div")
    @debug_el[:className] = "debug-overlay"
    @shadow.call(:appendChild, @debug_el)
    @debug_log = []
  end

  def log_debug(event_type, id, note = nil)
    return unless @debug

    entry = "#{event_type} id=#{id}"
    entry += " note=#{note}" if note
    @debug_log.push(entry)
    @debug_log.shift if @debug_log.size > 20

    active_ptrs = @pointers.map { |k, s| "#{k}:n#{s[:note]}" }.join(" ")
    midi_active = $midi_sender.active.to_a.sort.join(",")
    lines = [
      "<span class='info'>Active(#{@pointers.size}): [#{active_ptrs}]</span>",
      "<span class='info'>MIDI: [#{midi_active}]</span>",
      "---",
      *@debug_log.reverse.map { |l|
        l.include?("cancel") || l.include?("lost") ? "<span class='cancel'>#{l}</span>" : l
      }
    ]
    @debug_el[:innerHTML] = lines.join("<br>")
  end

  PadGrid.register("pad-grid")
end
