module Bankjob
  class OutputFormatter
    attr_reader :configuration

    def self.load_formatters
      formatter_pattern = File.join(File.dirname(__FILE__), 'output_formatter', '**', '*_formatter.rb')
      formatters = Dir[formatter_pattern]
      formatters.each do |formatter|
        require formatter
      end
    end

    def initialize(configuration)
      @configuration = configuration
    end

    def output(statement)
      formatter.output(statement)
    end

    private
    def formatter
      @formatter ||= begin
        name, arguments = configuration.split(/:/, 2)

        klass_name = name.gsub(/^[a-z]/i) { |c| c.upcase } + "Formatter"
        klass = Bankjob::OutputFormatter.const_get(klass_name)
        klass.new arguments
      end
    end
  end
end