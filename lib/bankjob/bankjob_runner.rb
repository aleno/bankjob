require 'rubygems'
require 'logger'
require 'bankjob.rb'

module Bankjob
  class BankjobRunner

    # Runs the bankjob application, loading and running the
    # scraper specified in the command line args and generating
    # the output file.
    def run(options, stdout)
      logger = options.logger

      Bankjob::OutputFormatter.load_formatters

      if options.output_formatters.empty?
        logger.debug "No output formatted specified so using the stdout formatter."
        options.output_formatters << Bankjob::OutputFormatter.new("stdout")
      end

      # Load the scraper object dynamically, then scrape the web
      # to get a new bank statement
      scraper = Scraper.load_scraper(options.scraper, options, logger)

      begin
        statement = scraper.scrape_statement(options.scraper_args)
        statement = Scraper.post_process_transactions(statement)
      rescue Exception => e
        logger.fatal(e)
        puts "Failed to scrape a statement successfully with #{options.scraper} due to: #{e.message}\n"
        puts "Use --debug --log bankjob.log then check the log for more details"
        exit (1)
      end

      options.output_formatters.each do |output_formatter|
        logger.debug "Outputting to #{output_formatter.configuration}"
        output_formatter.output statement
      end
    end
  end # class BankjobRunner
end # module Bankjob
