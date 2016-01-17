=begin
Code has been heavily simplified and obfuscated, but hopefully the general architecture comes across.
The purpose of this code is to create configurable filters sets that vary based on each locale/partner.
A complete filter set for a particular partner can be a hash that is 100+ lines long, so rather than maintain each
set I created base filter sets and had diffs applied to the base via callback functions.
This allowed us to scale very quickly for new locales/partners because all we had to do was apply the appropriate
callback to create a filter set.

Not shown for brevity sake:
- filter set generation is heavily cached
- Many more callbacks and base filter sets
- i18n translation support
=end

class FilterBuilder
  attr_accessor :filters

  CALLBACKS = Hash.new([]).merge(
                         {
                           [:ca, :oakland]         => BAY_AREA_CALLBACKS,
                           [:ca, :'san francisco'] => BAY_AREA_CALLBACKS,
                         }
                       ).freeze

  BAY_AREA_CALLBACKS = [
    {
      conditions: [{key: 'display_type', match: 'title'}, {key: 'name', match: 'gradeLevels'}],
      callback_type: 'append_to_children',
      options: {
        s: {label: 'Super Senior', display_type: :basic_checkbox, name: :gradeLevels, value: :s},
      }
    }
  ]

  SIMPLE_FILTERS = {
    display_type: :filter_column_primary,
    filters: {
      gradeLevels: {
        label: 'Grade Level',
        display_type: :title,
        name: :gradeLevels,
        filters: {
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
    @filters              = build_filter_tree({filter: SIMPLE_FILTERS.deep_clone})[0]
  end

  def build_filter_tree(filters)
    filters.map do |_, f|
      filter           = run_callbacks!(f)
      child_filters    = filter[:filters]
      filter[:filters] = build_filter_tree(child_filters) if child_filters.present?
      Filter.new(filter) if filter.present?
    end.compact
  end

  def run_callbacks!(filter)
    if @callbacks.present?
      @callbacks.each_with_index do |callback, i|
        callback_value = callback.call(filter)
        (@callbacks.delete_at(i) and return callback_value) if callback_value
      end
    else
      filter
    end
  end

  def build_callbacks
    CALLBACKS[@callback_set_key].map do |callback|
      try("build_#{callback[:callback_type]}_callback".to_sym, callback[:conditions], callback[:options])
    end.compact
  end

  def build_append_to_children_callback(conditions, new_filter)
    lambda do |filter|
      conditions.each do |condition|
        return false if filter[condition[:key].to_sym].to_s != condition[:match]
      end
      filter[:filters].present? ? (filter[:filters].merge!(new_filter) and filter) : new_filter
    end
  end

end
