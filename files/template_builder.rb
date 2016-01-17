=begin
Code has been heavily simplified and obfuscated, but hopefully the general architecture comes across.
The purpose of this code is to create configurable html template sets that vary based on each locale/partner.
A complete template set for a particular partner can be a hash that is 100+ lines long, so rather than maintain each
set I created base template sets and had diffs applied to the base via callback functions.
This allowed us to scale very quickly for new locales/partners because all we had to do was apply the appropriate
callbacks to create different template sets.

The example code below is for form form elements on a page

Also please overlook any errors that might have occured when obfuscating/simplifying this code :)

Not shown for brevity sake:
- Heavy caching for template set generation
- Many more callbacks and base template sets
- i18n translation support
- Error handling and logging
=end

class TemplateBuilder
  attr_accessor :templates

  CALLBACKS = Hash.new([]).merge({
                                   [:ca, :oakland]         => BAY_AREA_CALLBACKS,
                                   [:ca, :'san francisco'] => BAY_AREA_CALLBACKS,
                                 }).freeze

  BAY_AREA_CALLBACKS = [
    {
      conditions: [{key: 'display_type', match: 'title'}, {key: 'name', match: 'gradeLevels'}],
      callback_type: 'append_to_children',
      options: {
        s: {label: 'Super Senior', display_type: :basic_checkbox, name: :gradeLevels, value: :s},
      }
    }
  ]

  SIMPLE_TEMPLATE = {
    display_type: :template_column_primary,
    templates: {
      gradeLevels: {
        label: 'Grade Level',
        display_type: :title,
        name: :gradeLevels,
        templates: {
          p: {label: 'Preschool', display_type: :basic_checkbox, name: :gradeLevels, value: :p},
          e: {label: 'Elementary', display_type: :basic_checkbox, name: :gradeLevels, value: :e},
          m: {label: 'Middle', display_type: :basic_checkbox, name: :gradeLevels, value: :m},
          h: {label: 'High', display_type: :basic_checkbox, name: :gradeLevels, value: :h},
        }
      }
    }
  }

  def initialize(state = :no_state, city = :no_city)
    @callback_set_key     = [state.to_s.downcase.to_sym, city.to_s.downcase.to_sym]
    @callbacks            = build_callbacks
    @templates            = build_template_tree({template: SIMPLE_TEMPLATE.deep_clone})[0]
  end

  def build_template_tree(templates)
    templates.map do |_, temp|
      template           = run_callbacks!(temp)
      child_templates    = template[:templates]
      template[:templates] = build_template_tree(child_templates) if child_templates.present?
      Template.new(template) if template.present?
    end.compact
  end

  def run_callbacks!(template)
    if @callbacks.present?
      @callbacks.each_with_index do |callback, i|
        callback_value = callback.call(template)
        (@callbacks.delete_at(i) and return callback_value) if callback_value
      end
    else
      template
    end
  end

  def build_callbacks
    CALLBACKS[@callback_set_key].map do |callback|
      try("build_#{callback[:callback_type]}_callback".to_sym, callback[:conditions], callback[:options])
    end.compact
  end

  def build_append_to_children_callback(conditions, new_template)
    lambda do |template|
      conditions.each do |condition|
        return false if template[condition[:key].to_sym].to_s != condition[:match]
      end
      template[:templates].present? ? (template[:templates].merge!(new_template) and template) : new_template
    end
  end

end
