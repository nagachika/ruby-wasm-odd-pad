require 'js'

# Mixin that turns a Ruby class into a Web Component (custom element).
#
# Usage:
#   class MyWidget
#     include WebComponent
#
#     def connected_callback(js_element)
#       # build DOM here using JS gem
#     end
#
#     MyWidget.register("my-widget")
#   end
#
# Design note: connectedCallback in the generated JS class calls App.eval()
# to instantiate the Ruby object and delegate lifecycle methods.
# To avoid Ruby VM re-entrancy, the custom element must NOT already be in the
# DOM when register() is called.  Add the element to the DOM from JS *after*
# the require that triggers register() returns.
module WebComponent
  # id -> Ruby instance map, keyed by the integer stored on the JS element
  WC_REGISTRY = {}

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def register(tag_name)
      ruby_class_name = name   # e.g. "PadGrid"

      # Build the JS custom-element class as a string so we can embed the Ruby
      # class name.  The generated JS class delegates lifecycle callbacks back
      # into the Ruby VM via App.eval().
      js_code = <<~JS
        (() => {
          class RubyComponent extends HTMLElement {
            connectedCallback() {
              if (this.__rubyId !== undefined) return;  // already initialised

              // Allocate a Ruby instance and store its registry id on the element
              window.__wcElement = this;
              const id = App.eval(`
                inst = #{ruby_class_name}.new
                id   = WebComponent::WC_REGISTRY.size
                WebComponent::WC_REGISTRY[id] = inst
                this_elem = JS.global[:__wcElement]
                this_elem[:__rubyId] = id
                inst.connected_callback(this_elem)
                id
              `).toJS();
              delete window.__wcElement;
              this.__rubyId = id;
            }

            disconnectedCallback() {
              if (this.__rubyId === undefined) return;
              window.__wcElement = this;
              App.eval(`
                inst = WebComponent::WC_REGISTRY[JS.global[:__wcElement][:__rubyId].to_i]
                inst.disconnected_callback if inst
              `);
              delete window.__wcElement;
            }
          }

          customElements.define('#{tag_name}', RubyComponent);
        })();
      JS

      JS.eval(js_code)
      puts "[WebComponent] registered <#{tag_name}>"
    end
  end

  # Default stubs — subclasses override these
  def connected_callback(element); end
  def disconnected_callback; end
end
