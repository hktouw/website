=begin
This code has been heavily simplified and obfuscated from a project I worked,
but hopefully the general architecture comes across.
That being said, I still apologize for the length. Thank you for your understanding.

The purpose of this code is to create configurable html template sets that vary based on each locale/partner.
This is done by creating a tree of template objects where each node represents a bit of html.
The view then goes through the tree and generates the html using data from each template object.

A complete template set for a particular partner can be a hash that is 100+ lines long, so rather than maintain each
set I created base template sets and had diffs applied to the bases via callback functions.
This allowed us to scale very quickly for new locales/partners because all we had to do was apply the appropriate
callbacks to create different template sets.

The example code below is for a few form elements on a page
Also please overlook any errors that might have occured when obfuscating/simplifying this code :)

Not shown for brevity sake:
- Heavy caching for template set generation
- Many more callbacks and base template sets
- Many more attributes on the Template object
- Ids used in base template sets for more precise condition matching
- tests for TemplateCallbacks
- i18n translation support
- Error handling and logging
=end

module TemplateCallbacks

  BAY_AREA_CALLBACKS = [{
    conditions: [{key: 'partial', match: 'title'}, {key: 'name', match: 'gradeLevels'}],
    callback_type: 'append_to_children',
    options: {
      s: {label: 'Super Senior', partial: :basic_checkbox, name: :gradeLevels, value: :s},
    }
  }].freeze

  CALLBACKS = Hash.new([]).merge({
    [:ca, :oakland]         => BAY_AREA_CALLBACKS,
    [:ca, :'san francisco'] => BAY_AREA_CALLBACKS,
  }).freeze

  SIMPLE_TEMPLATE_SET = {
    partial: :template_column_primary,
    templates: {
      gradeLevels: {
        label: 'Grade Level',
        partial: :title,
        name: :gradeLevels,
        templates: {
          p: {label: 'Preschool', partial: :basic_checkbox, name: :gradeLevels, value: :p},
          e: {label: 'Elementary', partial: :basic_checkbox, name: :gradeLevels, value: :e},
          m: {label: 'Middle', partial: :basic_checkbox, name: :gradeLevels, value: :m},
          h: {label: 'High', partial: :basic_checkbox, name: :gradeLevels, value: :h},
        }
      }
    }
  }.freeze

  def run_callbacks!(template)
    @callbacks.try(:inject, template) { |t, c| c.call(template) }
    template
  end

  def build_callbacks(callbacks)
    callbacks.map do |callback|
      try("build_#{callback[:callback_type]}_callback".to_sym, callback[:conditions], callback[:options])
    end.compact
  end

  def build_append_to_children_callback(conditions, new_template)
    lambda do |template|
      return template unless conditions_match?(conditions, template)
      template[:templates] = template[:templates].to_hash.merge!(new_template)
      template
    end
  end

  def conditions_match?(conditions, template)
    conditions.each do |condition|
      return false if template[condition[:key].to_sym].to_s != condition[:match]
    end
  end

end


class TemplateBuilder
  include TemplateCallbacks
  attr_accessor :templates

  def initialize(state = :no_state, city = :no_city)
    callback_set_key   = [state.to_s.downcase.to_sym, city.to_s.downcase.to_sym]
    @callbacks         = build_callbacks(CALLBACKS[callback_set_key])
    @templates         = build_template_tree({_: SIMPLE_TEMPLATE_SET.deep_clone})[0]
  end

  def build_template_tree(templates)
    templates.map do |_, temp|
      template             = run_callbacks!(temp)
      child_templates      = template[:templates]
      template[:templates] = build_template_tree(child_templates) if child_templates.present?
      Template.new(template) if template.present?
    end.compact
  end
end


class Template
  attr_accessor :label, :name, :value, :partial, :templates, :has_children

  def initialize(attributes)
    @label = attributes[:label]
    @value = attributes[:value]
    @partial = attributes[:partial]
    @templates = attributes[:templates]
    @name = attributes[:name]
    @has_children = attributes[:templates].present?
  end

end


describe TemplateBuilder do
  include TemplateCallbacks

  # The test does not reuse callbacks/templates sets from the TemplateCallbacks module
  # This is intentional so that the tests do not depend on callbacks/templates from the module
  def bay_area_callbacks
    [{
      conditions: [{key: 'partial', match: 'title'}, {key: 'name', match: 'gradeLevels'}],
      callback_type: 'append_to_children',
      options: {
        s: {label: 'Super Senior', partial: :basic_checkbox, name: :gradeLevels, value: :s},
      }
    }]
  end

  def simple_template_set
    {
      partial: :template_column_primary,
      templates: {
        gradelevels: {
          label: 'Grade Level',
          partial: :title,
          name: :gradeLevels,
          templates: {
            p: {label: 'Preschool', partial: :basic_checkbox, name: :gradeLevels, value: :p},
            e: {label: 'Elementary', partial: :basic_checkbox, name: :gradeLevels, value: :e},
            m: {label: 'Middle', partial: :basic_checkbox, name: :gradeLevels, value: :m},
            h: {label: 'High', partial: :basic_checkbox, name: :gradeLevels, value: :h},
          }
        }
      }
    }
  end

  def should_have_template_with_callbacks_applied(base_template_set, template)
    base_template_set = run_callbacks!(base_template_set)
    if has_children?(base_template_set, template)
      base_template_set[:templates].values.each_with_index do | base_template, i |
        should_have_template_with_callbacks_applied(base_template, template.templates[i])
      end
    end
    templates_and_modified_base_template_set_should_be_eql(base_template_set, template)
  end

  def has_children?(base_template_set, template)
    expect(base_template_set[:templates].present?).to    eq(template.has_children)
    expect(base_template_set[:templates].try(:count)).to eq(template.templates.try(:count))
    template.has_children
  end

  def templates_and_modified_base_template_set_should_be_eql(base_template_set, template)
    expect(base_template_set[:partial]).to eq(template.partial)
    expect(base_template_set[:label]).to   eq(template.label)
    expect(base_template_set[:name]).to    eq(template.name)
    expect(base_template_set[:value]).to   eq(template.value)
    expect(base_template_set[:label]).to   eq(template.label)
  end

  # this lets us easily add test coverage for new partners/locales
  [
    [[:ca, :oakland], :simple_template_set, :bay_area_callbacks],
    [[:ca, :'san francisco'], :simple_template_set, :bay_area_callbacks]
  ].each do | locale, base_template_set, callback_applied |
    context "when testing #{locale}" do
      it "should have the #{callback_applied} to the #{base_template_set}" do
        templates          = TemplateBuilder.new(*locale).templates
        base_template_set  = send(base_template_set)
        @callbacks         = build_callbacks(send(callback_applied))
        should_have_template_with_callbacks_applied(base_template_set, templates)
      end
    end
  end

end

