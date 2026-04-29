require 'js'
require 'web_component'

class DimCtrl
  include WebComponent

  def connected_callback(element)
    doc = JS.global[:document]
    element[:className] = "ctrl-group"

    label = doc.call(:createElement, "label")
    label[:htmlFor] = "ctrl-dim"
    label[:textContent] = "Dim"

    select = doc.call(:createElement, "select")
    select[:id] = "ctrl-dim"
    [3, 4, 5].each do |v|
      opt = doc.call(:createElement, "option")
      opt[:value] = v.to_s
      opt[:textContent] = v.to_s
      opt[:selected] = true if v == 3
      select.call(:appendChild, opt)
    end
    select.call(:addEventListener, "change", proc { |e|
      $midi_sender.send_cc(20, e[:target][:value].to_i)
    })

    element.call(:appendChild, label)
    element.call(:appendChild, select)
  end

  DimCtrl.register("dim-ctrl")
end

class VolCtrl
  include WebComponent

  def connected_callback(element)
    doc = JS.global[:document]
    element[:className] = "ctrl-group"

    label = doc.call(:createElement, "label")
    label[:htmlFor] = "ctrl-volume"
    label[:textContent] = "Vol"

    input = doc.call(:createElement, "input")
    input[:type] = "range"
    input[:id] = "ctrl-volume"
    input[:min] = "0"
    input[:max] = "127"
    input[:value] = "100"
    input[:step] = "1"
    input.call(:addEventListener, "input", proc { |e|
      $midi_sender.send_cc(7, e[:target][:value].to_i)
    })

    element.call(:appendChild, label)
    element.call(:appendChild, input)
  end

  VolCtrl.register("vol-ctrl")
end
