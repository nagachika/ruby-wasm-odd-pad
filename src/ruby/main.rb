require 'js'
require 'set'
require 'web_component'
require 'midi_sender'
require 'pad_grid'   # triggers PadGrid.register("pad-grid") at load time

# Global MIDI sender — used by PadGrid event handlers and JS control wire-up
$midi_sender = MidiSender.new

puts "[main] Ruby boot complete. <pad-grid> registered."
