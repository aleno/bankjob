require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that HbosScraper extends
require 'activesupport'

require 'ruby-debug'
require 'highline/import'
HighLine.track_eof = false

include Bankjob        # access the namespace of Bankjob

SORT_CODE         = 0
ACCOUNT_NUMBER    = 1
ROLL_NUMBER       = 2
BALANCE           = 3
OVERDRAFT_LIMIT   = 4
AVAILABLE_BALANCE = 5

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
  account_number "1234567" # override this with a real accoun number
  account_type Statement::CHECKING # this is the default anyway

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
      statement_links.map { |link| link.inner_html }.each_with_index do |account_number,index|
        puts "[#{index}] - #{account_number}"
      end
      choice = ask("Which account do you want to scrape?")
    
      link_for_chosen_account = agent.page.links.detect { |link|
        # link.class                  =>   WWW::Mechanize::Page::Link
        # statement_links[x].class    =>   Hpricot::Elem
        link.text == statement_links[choice.to_i].inner_html
      }
    
      @account_name = link_for_chosen_account.text
      transactions_page = link_for_chosen_account.click
    end

    logger.info("Logged in, now navigating to transactions on #{link_for_chosen_account.uri}.")
    if (transactions_page.nil?)
      raise "HBOS Scraper failed to load the transactions page at #{link_for_chosen_account.uri}"
    end
    return transactions_page
  end


  ##
  # Parses the HBOS page listing about a weeks worth of transactions
  # and creates a Transaction for each one, putting them together
  # in a Statement.
  # Overrides (implements) +parse_transactions_page+ in BaseScraper.
  #
  def parse_transactions_page(transactions_page)
    begin
      statement = create_statement

      statement.bank_id, statement.account_number = *@account_name.strip.split(/ /, 2).map{|s|s.strip}
      summary_cells = (transactions_page/".summaryBoxesValues")
      statement.bank_id, statement.account_number = *@account_name.strip.split(/ /, 2).map{|s|s.strip}
      closing_available = summary_cells[AVAILABLE_BALANCE].inner_text.gsub("\243", '').gsub("\226", '-').gsub(',',"").gsub(' ', '').to_f
      statement.closing_available = closing_available
      closing_balance = summary_cells[BALANCE].inner_text.gsub("\243", '').gsub("\226", '-').gsub(',',"").gsub(' ', '').to_f
      statement.closing_balance = closing_balance

      transactions = []
      table = (transactions_page/"#frmStatement table")
      rows = (table/"tr")
      date_tracker = nil
      Struct.new("Line", :date, :description, :money_out, :money_in, :balance)
      current_line = Struct::Line.new
      previous_line = Struct::Line.new
      rows.each_with_index do |row,index|
        next if index == 0 # first row is just headers

        transaction = create_transaction # use the support method because it sets the separator

        # collect all of the table cells' inner html in an array (stripping leading/trailing spaces)
        previous_line = current_line
        data = (row/"td").collect{ |cell| cell.inner_html.strip.gsub(/&nbsp;/, "") }
        current_line = Struct::Line.new(*data)

        # When consecutive transactions occur on the same date, the date is only displayed on the
        # first row. So if current line has no date, get the date from the previous line.
        if current_line.date.blank?
          current_line.date = previous_line.date
        end

        # Check if previous line was blank. If so, merge its description into the current line description.
        if blank_line?(previous_line)
          current_line.description = [current_line.description, previous_line.description].join(", ")
        end
        
        # Rows with no money in or out value just contain extra description. Skip these.
        next if blank_line?(current_line)
        amount = current_line.money_out.blank? ?
          current_line.money_in :
          "-" + current_line.money_out

        transaction.date            = current_line.date
        transaction.raw_description = current_line.description
        transaction.amount          = amount
        transaction.new_balance     = current_line.balance

        transactions << transaction
      end
    rescue => exception
      msg = "Failed to parse the transactions page at due to exception: #{exception.message}\nCheck your user name and password."
      logger.fatal(msg);
      logger.debug(exception)
      logger.debug("Failed parsing transactions page:")
      logger.debug("--------------------------------")
      logger.debug(transactions_page) #.body
      logger.debug("--------------------------------")
      abort(msg)
    end

    # set the transactions on the statement
    statement.transactions = transactions
    return statement
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

    username, password = *scraper_args unless scraper_args.nil?
    form.Username = username || ask("username:\n")
    form.password = password || ask("password:\n") { |q| q.echo = "•" }

    prompts = agent.page.search(".LoginPrompt")
    if question = prompts[2].inner_html.strip rescue nil
      form.answer          = ask( question ) { |q| q.echo = "•" }
    end

    agent.submit(form)
    sleep 3  # wait while the login takes effect
  end

  private

  def parse_scraper_args(args)
    key_indices = (0..args.size).to_a.select{ |v| v % 2 == 0 }
    value_indices = (0..args.size).to_a.select{ |v| v % 2 == 1 }
    answers = {}
    key_indices.size.times do |i|
      answers[args[key_indices[i]]] = args[value_indices[i]]
    end
    answers
  end

  def blank_line?(line)
    line.money_out.blank? and line.money_in.blank?
  end

end # class HbosScraper


