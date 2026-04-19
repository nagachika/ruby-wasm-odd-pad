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
    .pad.active        { background: #4dabf7; }
    .pad.root.active   { background: #69db7c; }
  CSS

  def connected_callback(js_element)
    @element = js_element
    @shadow  = @element.call(:attachShadow, JS.eval("return { mode: 'open' }"))
    inject_style
    render_grid
    attach_events
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
    # Pass procs as positional arguments so JS gem converts them to JS functions.
    # Using &block form with call() passes as a block, not as the JS argument.
    on_down   = method(:on_pointerdown).to_proc
    on_up     = method(:on_pointerup).to_proc
    @grid.call(:addEventListener, "pointerdown",   on_down)
    @grid.call(:addEventListener, "pointerup",     on_up)
    @grid.call(:addEventListener, "pointercancel", on_up)
  end

  def on_pointerdown(event)
    target = event[:target]
    note_val = target[:dataset][:note]
    return if note_val.typeof == "undefined" || note_val.to_s.empty?

    event.call(:preventDefault)
    target.call(:setPointerCapture, event[:pointerId])

    note     = note_val.to_i
    velocity = calc_velocity(event, target)

    target[:classList].call(:add, "active")
    $midi_sender.note_on(note, velocity)
  end

  def on_pointerup(event)
    target = event[:target]
    note_val = target[:dataset][:note]
    return if note_val.typeof == "undefined" || note_val.to_s.empty?

    target[:classList].call(:remove, "active")
    $midi_sender.note_off(note_val.to_i)
  end

  def calc_velocity(event, target)
    width = event[:width].to_f
    if width > 1
      # Touch: scale contact width (CSS px) to velocity
      (width / 50.0 * 127).round.clamp(1, 127)
    else
      # Mouse / stylus without pressure: use vertical position within pad
      rect  = target.call(:getBoundingClientRect)
      rel_y = 1.0 - (event[:clientY].to_f - rect[:top].to_f) / rect[:height].to_f
      (rel_y * 100 + 27).round.clamp(1, 127)
    end
  end

  # Register at class-load time.
  # IMPORTANT: The <pad-grid> element must not be in the DOM at this moment;
  # it is appended by main.js after require 'main' returns.
  PadGrid.register("pad-grid")
end
