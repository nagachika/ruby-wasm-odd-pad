require 'js'
require 'set'
require 'web_component'
require 'midi_sender'
require 'ctrl_group'   # registers <dim-ctrl> and <vol-ctrl>
require 'kebab_menu'   # registers <kebab-menu>
require 'midi_out_ctrl' # registers <midi-out-ctrl>
require 'pad_grid'     # triggers PadGrid.register("pad-grid") at load time

# Global MIDI sender — used by PadGrid event handlers and JS control wire-up
$midi_sender = MidiSender.new

puts "[main] Ruby boot complete. <pad-grid> registered."
