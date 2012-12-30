# encoding: UTF-8

require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that BpiScraper extends

include Bankjob        # access the namespace of Bankjob

##
# SwedbankScraper is a scraper tailored to the Swedbank bank in Sweden (www.swedbank.se).
# It takes advantage of the BaseScraper to create the mechanize agent,
# then followins the basic recipe there of first loading the tranasctions page
# then parsing it.
#
# SwedbankScraper expects the user name and password to be passed on the command line
# using --scraper-args "user password" (with a space between them).
#
class SwedbankScraper < BaseScraper

  currency  "SEK" # Set the currency as euros
  decimal   ","    # Swedbank statements use commas as separators - this is used by the real_amount method
  account_number "1234567" # override this with a real account number
  account_type Statement::CHECKING # this is the default anyway

  # Some constants for the URLs and main elements in the Swedbank bank app
  LOGIN_URL = 'https://internetbank.swedbank.se/bviPrivat/privat?ns=1'
  TRANSACTIONS_URL = 'Privatkonto'

  ##
  # Uses the mechanize web +agent+ to fetch the page holding the most recent
  # bank transactions and returns it.
  # This overrides (implements) +fetch_transactions_page+ in BaseScraper
  #
  def fetch_transactions_page(agent)
    agent.user_agent_alias = 'Mac Safari' # pretend where safari to avoid annoying warning about insecure browser 
    login(agent)
    logger.info("Logged in, now navigating to transactions on #{TRANSACTIONS_URL}.")

    transactions_page = agent.page.link_with(:text => TRANSACTIONS_URL).click
    if (transactions_page.nil?)
      raise "Swedbank Scraper failed to load the transactions page at #{TRANSACTIONS_URL}"
    end

    # fetch all entries
    agent.page.link_with(:text => 'Visa alla').click
    agent.page.link_with(:text => 'Hämta fler').click
    transactions_page = agent.page.link_with(:text => 'Hämta fler').click
   
    return transactions_page
  end

  
  ##
  # Parses the Swedbank page listing about a weeks worth of transactions
  # and creates a Transaction for each one, putting them together
  # in a Statement.
  # Overrides (implements) +parse_transactions_page+ in BaseScraper.
  #
  def parse_transactions_page(transactions_page)
    begin
      statement = create_statement

      bank_id, account_number = get_account_number(transactions_page)
      statement.account_number = account_number unless account_number.nil?
      statement.bank_id = bank_id unless bank_id.nil?


      rows = transactions_page.search("//div[@class='sektion-innehall2']/table[@class='tabell']").last.search(
          ".//td[@class='tabell-cell-topp']/..",
          ".//td[@class='tabell-cell']/..",
          ".//td[@class='tabell-cell-botten']/..")
      rows.each do |row|
        transaction = create_transaction # use the support method because it sets the separator

        # collect all of the table cells' inner text in an array (stripping leading/trailing spaces)
        data = row.search("td").collect{ |cell| cell.content.gsub(/(^\p{Space}|\p{Space}$)/, '') }
	
        # the first (0th) column holds the date
        transaction.date = data[0]

        # the transaction raw_description is in the 3rd column
        transaction.raw_description = data[2]

        # the 4th column holds the transaction amount (with comma as decimal place)
        transaction.amount = Money.parse(data[4], 'SEK')

        # the new balance is in the last column
        transaction.new_balance = Money.parse(data[5], 'SEK')
        
        # add the new transaction to the array
        statement.add_transaction(transaction)
        #	break if $debug
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

    # finish the statement to set the balances and dates
    # and to fake the times since the bpi web pages
    # don't hold the transaction times
    statement.finish(true, true)

    return statement
  end

  def get_account_number(transactions_page)
    account_number = transactions_page.search('div.sektion-huvud h3.mellanrubrik')[0].content.gsub(/[^0-9\-\,\ ]/,"")
    return account_number.split(/,/, 2).map{|s|s.strip}
  end

  ##
  # Logs into the Swedbank banking app by finding the form
  # setting the name and password and submitting it then
  # waits a bit.
  #
  def login(agent)
    logger.info("Logging in to #{LOGIN_URL}.")
    if (scraper_args)
      username, password = *scraper_args
    end
    raise "Login failed for Swedbank Scraper - pass user name and password using -scraper_args \"user <space> pass\"" unless (username and password)

    # navigate to the login page
    login_page = agent.get(LOGIN_URL)
    # Landing page requires redirect
    login_page = agent.submit(login_page.form('form1'))
    # find login form - it's called 'auth' - fill it out and submit it
    form = login_page.form('auth')
    # username and password are taken from the commandline args, set them
    # on USERID and PASSWORD which are the element names that the web page
    # form uses to identify the form fields
    form["auth:kundnummer"] = username
    form["auth:metod_2"] = "PIN6"

    # submit the form - same as the user hitting the Login button
    login_page = agent.submit(form, form.buttons.first)
                
    # Step 2 is to enter the password
    form = login_page.form('form')

    form["form:pinkod"] = password
    login_page = agent.submit(form, form.buttons.first)
                             
    # After login an additional direct is required.
    agent.submit(login_page.form('redirectForm'))
    # sleep 3  # wait while the login takes effect
  end
end # class SwedbankScraper


