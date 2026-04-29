require 'js'
require 'set'

class MidiSender
  NOTE_ON  = 0x90
  NOTE_OFF = 0x80
  CC       = 0xB0
  CHANNEL  = 0  # MIDI channel 1 (0-indexed)

  attr_reader :active

  def initialize
    @active = Set.new
  end

  def note_on(note_number, velocity = 100)
    return if note_number < 0 || note_number > 127
    velocity = velocity.clamp(1, 127)
    send_raw(NOTE_ON | CHANNEL, note_number, velocity)
    @active.add(note_number)
  end

  def note_off(note_number)
    return unless @active.delete?(note_number)
    send_raw(NOTE_OFF | CHANNEL, note_number, 0)
  end

  def all_notes_off
    @active.dup.each { |n| note_off(n) }
  end

  def send_cc(cc_number, value)
    send_raw(CC | CHANNEL, cc_number, value.clamp(0, 127))
  end

  private

  def send_raw(status, data1, data2)
    JS.global[:App].call(:sendMidi, status, data1, data2)
  end
end
