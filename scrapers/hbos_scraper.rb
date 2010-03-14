require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that HbosScraper extends
require 'activesupport'

require 'ruby-debug'
require 'highline/import'
HighLine.track_eof = false

require 'digest/sha1'
require 'yaml'

include Bankjob        # access the namespace of Bankjob

SORT_CODE         = 0
ACCOUNT_NUMBER    = 1
ROLL_NUMBER       = 2
BALANCE           = 3
OVERDRAFT_LIMIT   = 4
AVAILABLE_BALANCE = 5

class HbosString < String
  # HBos fill empty cells with \240 for some reason. Crazy.
  def blank?
    super || self == "\240"
  end

  def to_f
    # We're going to do lots of substitution so let's do it in-place to
    # avoid creating lots of objects. Of course, we don't want to mutate
    # the original string so lets use a duplicate.
    str = String.new(dup)
    # Strip the £ symbol.
    str.gsub!("\243", '')
    # Swap the crazy minus symbol for a dash like would be expected.
    str.gsub!("\226", '-')
    # Strip commas or the float will be truncated as the first comma.
    str.gsub!(',',"")
    # Same idea with spaces as with commas.
    str.gsub!(' ', '')
    # We should be safe to convert to a float now.
    str.to_f
  end
end

class HbosAnswerAgent
  def initialize(configuration)
    @configuration = configuration
  end

  def answer(question)
    key = Digest::SHA1.hexdigest(question.to_s.downcase)
    lookup(key)
  end

  private
  def lookup(key)
    YAML.load_file(@configuration)[key]
  end
end

class HbosCurrentAccountTransactionParser
  def parse_into_statement(transactions_page, statement)
    summary_cells = (transactions_page/".summaryBoxesValues")
    closing_available = HbosString.new(summary_cells[AVAILABLE_BALANCE].inner_text).to_f
    statement.closing_available = closing_available
    closing_balance =  HbosString.new(summary_cells[BALANCE].inner_text).to_f
    statement.closing_balance = closing_balance

    transactions = []
    table = (transactions_page/"#frmStatement table")
    rows = (table/"tr")
    date_tracker = nil
    Struct.new("Line", :date, :description, :money_out, :money_in, :balance)
    current_line = nil
    previous_line = Struct::Line.new
    current_date = nil
    rows.each_with_index do |row,index|
      next if index == 0 # first row is just headers

      transaction = Bankjob::Transaction.new ","

      # collect all of the table cells' inner html in an array (stripping leading/trailing spaces)
      previous_line = current_line
      data = (row/"td").collect{ |cell| cell.inner_html.strip.gsub(/&nbsp;/, "") }
      current_line = Struct::Line.new(*data)
      next if blank_line?(current_line)

      current_date ||= current_line.date
      # When consecutive transactions occur on the same date, the date is only displayed on the
      # first row. So if current line has no date, get the date from the previous date.
      if HbosString.new(current_line.date).blank?
        current_line.date = current_date
      else
        current_date = current_line.date
      end

      # Check if previous line was blank. If so, merge its description into the current line description.
      if previous_line && blank_line?(previous_line)
        current_line.description = [current_line.description, previous_line.description].join(", ")
      end

      # Rows with no money in or out value just contain extra description. Skip these.
      amount = HbosString.new(current_line.money_out).blank? ?
        current_line.money_in : "-" + current_line.money_out

      transaction.date            = current_line.date
      transaction.raw_description = current_line.description
      transaction.amount          = amount
      transaction.new_balance     = current_line.balance

      statement.transactions << transaction
    end
  end

  private
  def blank_line?(line)
    HbosString.new(line.money_out).blank? and HbosString.new(line.money_in).blank?
  end
end

class HbosTransactionParser
  attr_reader :account_type

  def initialize(account_type)
    @account_type = account_type
  end

  def parser_implementation
    case account_type
    when "Bank of Scotland Current Account"
      HbosCurrentAccountTransactionParser.new
    else
      raise "Could not work out the parser type to use for '#{account_type}'"
    end
  end

  def method_missing(method_name, *args)
    parser_implementation.send(method_name, *args)
  end
end

##
# HbosScraper is a scraper tailored to the HBOS bank in the UK (http://www.bankofscotland.co.uk/).
# It takes advantage of the BaseScraper to create the mechanize agent,
# then followins the basic recipe there of first loading the tranasctions page
# then parsing it.
#
# In addition to actually working for the HBOS online banking, this class serves
# as an example of how to build your own scraper.
#
# HbosScraper expects the user name and password to be passed on the command line
# using -scraper_args "user password" (with a space between them).
#
class HbosScraper < BaseScraper

  currency  "GBP" # Set the currency as euros
  decimal   "."    # HBOS statements use periods as separators - this is used by the real_amount method
  account_type Statement::CHECKING # this is the default anyway
  account_number "1234567890" # gets overridden later

  # This rule detects ATM withdrawals and modifies
  # the description and sets the the type
  transaction_rule do |tx|
    if (tx.real_amount < 0)
      if tx.raw_description =~ /LEV.*ATM ELEC\s+\d+\/\d+\s+/i
        tx.description = "Multibanco withdrawal at #{$'}"
        tx.type = Transaction::ATM
      end
    end
  end

  # This rule detects checque payments and modifies the description
  # and sets the type
  transaction_rule do |tx|
    if tx.raw_description =~ /CHEQUE\s+(\d+)/i
      cheque_number = $+   # $+ holds the last group of the match which is (\d+)
      # change the description but append $' in case there was trailing text after the cheque no
      tx.description = "Cheque ##{cheque_number} withdrawn #{$'}"
      tx.type = Transaction::CHECK
      tx.check_number = cheque_number
    end
  end

  # This rule goes last and sets the description of transactions
  # that haven't had their description to the raw description after
  # changing the words to have capital letters only on the first word.
  # (Note that +description+ will default to being the same as +raw_description+
  #  anyway - this rule is only for making the all uppercase output less ugly)
  # The payee is also fixed in this way
  transaction_rule(-999) do |tx|
    if (tx.description == tx.raw_description)
      tx.description = Bankjob.capitalize_words(tx.raw_description)
    end
  end

  # Some constants for the URLs and main elements in the HBOS bank app
  LOGIN_URL = 'https://www.bankofscotlandhalifax-online.co.uk/_mem_bin/formslogin.asp'
  TRANSACTIONS_URL = ''

  ##
  # Uses the mechanize web +agent+ to fetch the page holding the most recent
  # bank transactions and returns it.
  # This overrides (implements) +fetch_transactions_page+ in BaseScraper
  #
  def fetch_transactions_page(agent)
    login(agent)
    
    statement_links = (agent.current_page/"#ctl00_MainPageContent_MyAccountsCtrl_tbl a")
    if statement_links.blank?
      puts "Wait a bit, and try again later." and return
    else
      open_account_page(agent)
    end
  end

  def open_account_page(agent)
    link = if target_account.blank?
      statement_links.map { |link| link.inner_html }.each_with_index do |account_number,index|
        puts "[#{index}] - #{account_number}"
      end
      choice = ask("Which account do you want to scrape?")
  
      agent.page.links.detect { |link|
        link.text == statement_links[choice.to_i].inner_html
      }
    else
      @account_name = target_account
      agent.page.link_with(:text => @account_name)
    end

    account_type = (link.node.parent / "text()")[1].to_s
    @transaction_parser = HbosTransactionParser.new(account_type)
    @account_name = link.text
    link.click
  end

  def target_account
    if scraper_args.size > 3
      scraper_args[3..-1].join(' ')
    end
  end

  ##
  # Parses the HBOS page listing about a weeks worth of transactions
  # and creates a Transaction for each one, putting them together
  # in a Statement.
  # Overrides (implements) +parse_transactions_page+ in BaseScraper.
  #
  def parse_transactions_page(transactions_page)
    statement = create_statement
    statement.bank_id, statement.account_number = *@account_name.strip.split(/ /, 2).map{|s|s.strip}
    @transaction_parser.parse_into_statement(transactions_page, statement)
    statement
  rescue => exception
    msg = "Failed to parse the transactions page. Check your user name and password are correct."
    logger.fatal(msg);
    logger.debug("(stacktrace) #{exception.message}")
    exception.backtrace.each do |line|
      logger.debug("(stacktrace) #{line}")
    end
    logger.debug("Failed parsing transactions page:")
    logger.debug("--------------------------------")
    logger.debug(transactions_page) #.body
    logger.debug("--------------------------------")
    abort(msg)
  end

  ##
  # Logs into the HBOS banking app by finding the form
  # setting the name and password and submitting it then
  # waits a bit.
  #
  def login(agent)
    logger.info("Logging in to #{LOGIN_URL}.")

    login_page = agent.get(LOGIN_URL)
    form  = login_page.form('frmFormsLogin')

    username, password, answer_agent = *scraper_args unless scraper_args.nil?
    form.Username = username || ask("username:\n")
    form.password = password || ask("password:\n") { |q| q.echo = "•" }

    prompts = agent.page.search(".LoginPrompt")
    question = prompts[2].inner_html.strip

    if answer_agent.blank?
      if question = prompts[2].inner_html.strip rescue nil
        form.answer = ask( question ) { |q| q.echo = "•" }
      end
    else
      answer_agent = HbosAnswerAgent.new(answer_agent)
      form.answer = answer_agent.answer(question)
    end

    agent.submit(form)
  end
end # class HbosScraper


