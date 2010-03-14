require 'rubygems'
require 'ostruct'
require 'optparse'
require 'logger'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'bankjob_runner'
require 'output_formatter'

module Bankjob
  class CLI

    NEEDED = "Needed" # constant to indicate compulsory options
    NOT_NEEDED = "Not Needed" # constant to indicate no-longer compulsory options

    def self.execute(stdout, argv)
      # The BanjobOptions module above, through the magic of OptiFlags
      # has augmented ARGV with the command line options accessible through
      # ARGV.flags.
      runner = BankjobRunner.new
      runner.run(parse(argv), stdout)
    end # execute

    ##
    # Parses the command line arguments using OptionParser and returns
    # an open struct with an attribute for each option
    #
    def self.parse(args)
      options = OpenStruct.new

      # Set the default options
      options.scraper = NEEDED
      options.scraper_args = []
      options.log_level = Logger::WARN
      options.log_file = nil
      options.debug = false
      options.input = nil
      options.output_formatters = []
      options.logger = nil

      opt = OptionParser.new do |opt|
        opt.banner = "Bankjob - scrapes your online banking website for transaction details.\n" +
                     "Transaction details can be output in a number of formats.\n" +
                     "\n" +
                     "Usage: bankjob [options]\n"

        opt.version = Bankjob::BANKJOB_VERSION
  
        opt.on('-s', '--scraper SCRAPER',
               "The name of the ruby file that scrapes the website.\n") do |file|
          options.scraper = file
        end

        opt.on('--scraper-args ARGS',
               "Any arguments you want to pass on to your scraper.",
               "The entire set of arguments must be quoted and separated by spaces",
               "but you can use single quotes to specify multi-word arguments for",
               "your scraper.  E.g.",
               "   -scraper-args \"-user Joe -password Joe123 -arg3 'two words'\""," ",
               "This assumes your scraper accepts an array of args and knows what",
               "to do with them, it will vary from scraper to scraper.\n") do |sargs|
          options.scraper_args = sub_args_to_array(sargs)
        end

        opt.on('-i', '--input INPUT_HTML_FILE',
               "An html file used as the input instead of scraping the website -",
               "useful for debugging.\n") do |file|
          options.input = file
        end

        opt.on('-l', '--log LOG_FILE',
               "Specify a file to log information and debug messages.",
               "If --debug is used, log info will go to the console, but if neither",
               "this nor --debug is specfied, there will be no log.",
               "Note that the log is rolled over once per week\n") do |log_file|
          options.log_file = log_file
        end

        opt.on('q', '--quiet', "Suppress all messages, warnings and errors.",
               "Only fatal errors will go in the log") do
          options.log_level = Logger::FATAL
        end

        opt.on( '--verbose', "Log detailed informational messages.\n") do
          options.log_level = Logger::INFO
        end

        opt.on('--debug',
               "Log debug-level information to the log",
               "if here is one and put debug info in log\n") do
          options.log_level = Logger::DEBUG
          options.debug = true
        end

        opt.on('--out FORMATTER',
                "Format output using this formatter. Default: stdout.") do |configuration|
          formatter = Bankjob::OutputFormatter.new(configuration)
          options.output_formatters << formatter
        end

        opt.on('--version', "Display program version and exit.\n" ) do
          puts opt.version
          exit
        end
 
        opt.on_tail('-h', '--help', "Display this usage message and exit.\n" ) do
          puts opt
          exit!
        end
  
      end #OptionParser.new

      begin
        opt.parse!(args)
        _validate_options(options) # will raise exceptions if options are invalid
        _init_logger(options) # sets the logger
      rescue Exception => e
        puts e, "", opt
        exit
      end
  
      return options
    end #self.parse

    private

    # Checks if the options are valid, raising exceptiosn if they are not.
    # If the --debug option is true, then messages are dumped but flow continues
    def self._validate_options(options)
      begin 
        #Note that OptionParser doesn't really handle compulsory arguments so we use
        #our own mechanism
        if options.scraper == NEEDED
          raise "Incomplete arguments: You must specify a scraper ruby script with --scraper"
        end

        # Set output to stdout if it's not been set
        options.ofx = true unless options.csv or options.wesabe_upload
      rescue Exception => e
        if options.debug
          # just dump the message and eat the exception - 
          # we may be using dummy values for debugging
          puts "Ignoring error in options due to --debug flag: #{e}"
        else
          raise e
        end
      end #begin/rescue

    end #_validate_options

    ##
    # Initializes the logger taking the log-level and the log
    # file name from the command line +options+ and setting the logger back on
    # the options struct as +options.logger+
    #
    # Note that the level is not set explicitly in options but derived from
    # flag options like --verbose (INFO), --quiet (FATAL) and --debug (DEBUG)
    #
    def self._init_logger(options)
      # the log log should roll over weekly
      if options.log_file.nil?
        if options.debug 
          # if debug is on but no logfile is specified then log to console
          options.log_file = STDOUT
        else
          # Setting the log level to UNKNOWN effectively turns logging off
          options.log_level = Logger::UNKNOWN
        end
      end
      options.logger = Logger.new(options.log_file, 'weekly') # roll over weekly
      options.logger.level = options.log_level
    end
   
    # Takes a string of arguments and splits it into an array, allowing for 'single quotes'
    # to join words into a single argument.
    # (Note that parentheses are used to group to exclude the single quotes themselves, but grouping
    #  results in scan creating an array of arrays with some nil elements hence flatten and delete)
    def self.sub_args_to_array(subargs)
      return nil if subargs.nil?
      return subargs.scan(/([^\s']+)|'([^']*)'/).flatten.delete_if { |x| x.nil?}
    end

  end #class CLI
end
