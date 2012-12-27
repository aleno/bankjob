# encoding: utf-8
#
require 'rubygems'
require 'bankjob'

module Bankjob

  ##
  # Takes a date-time as a string or as a Time or DateTime object and returns
  # it as either a Time object.
  #
  # This is useful in the setter method of a date attribute allowing the date
  # to be set as any type but stored internally as an object compatible with
  # conversion through +strftime()+
  # (Bankjob::Transaction uses this internally in the setter for +date+ for example
  #
  def self.create_date_time(date_time_raw)
    if (date_time_raw.is_a?(Time)) then
      # It's already a Time 
      return date_time_raw
    elsif (date_time_raw.to_s.strip.empty?)
      # Nil or non dates are returned as nil
      return nil
    else
      # Assume it can be converted to a time
      return Time.parse(date_time_raw.to_s)
    end
  end

  ##
  # Takes a string and capitalizes the first letter of every word
  # and forces the rest of the word to be lowercase.
  #
  # This is a utility method for use in scrapers to make descriptions
  # more readable.
  #
  def self.capitalize_words(message)
    message.downcase.gsub(/\b\w/){$&.upcase}
  end

  ##
  # converts a numeric +string+ to a float given the specified +decimal+
  # separator.
  #
  def self.string_to_float(string, decimal)
    return nil if string.nil?
    return string.to_f if string.kind_of?(Money)
    amt = string.gsub(/\p{Space}/, '')
    if (decimal == ',') # E.g.  "1.000.030,99"
      amt.gsub!(/\./, '')  # strip out . 1000s separator
      amt.gsub!(/,/, '.')  # replace decimal , with .
    elsif (decimal == '.')
      amt.gsub!(/,/, '')  # strip out comma 1000s separator
    end
    return amt.to_f
  end

  ##
  # Finds a selector field in a named +form+ in the given Mechanize +page+, selects
  # the suggested +label+
  def select_and_submit(page, form_name, select_name, selection)
    option = nil
    form  = page.form(form_name)
    unless form.nil?
      selector = form.field(select_name)
      unless selector.nil?
        option = select_option(selector, selection)
        form.submit
      end
    end
    return option
  end

  ##
  # Given a Mechanize::Form:SelectList +selector+ will attempt to select the option
  # specified by +selection+.
  # This algorithm is used:
  #   The first option with a label equal to the +selection+ is selected.
  #    - if none is found then -
  #   The first option with a value equal to the +selection+ is selected.
  #    - if none is found then -
  #   The first option with a label or value that equal to the +selection+ is selected
  #   after removing non-alphanumeric characters from the label or value
  #    - if none is found then -
  #   The first option with a lable or value that _contains_ the +selection+
  #
  # If matching option is found, the #select is called on it.
  # If no option is found, nil is returned - otherwise the option is returned
  #
  def select_option(selector, selection)
    options = selector.options.select { |o| o.text == selection }
    options = selector.options.select { |o| o.value == selection } if options.empty?
    options = selector.options.select { |o| o.text.gsub(/[^a-zA-Z0-9]/,"") == selection } if options.empty?
    options = selector.options.select { |o| o.value.gsub(/[^a-zA-Z0-9]/,"") == selection } if options.empty?
    options = selector.options.select { |o| o.text.include?(selection) } if options.empty?
    options = selector.options.select { |o| o.value.include?(selection) } if options.empty?

    option = options.first
    option.select() unless option.nil?
    return option
  end
end # module Bankjob


