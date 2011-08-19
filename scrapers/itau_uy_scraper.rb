require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that ItauUYScraper extends
require 'pathname'

include Bankjob        # access the namespace of Bankjob

##
# ItauUYScraper is a scraper tailored to the Itau bank in Uruguay (www.itaulink.com.uy).
# It takes advantage of the BaseScraper to create the mechanize agent,
# then followins the basic recipe there of first loading the tranasctions page
# then parsing it.
#
# This scraper is based on the bci_scraper.
#
# ItauUYScraper expects the user name and password to be passed on the command line
# using --scraper-args "user password" (with a space between them).
# Optionally, the account number can also be specified with the 3rd argument so:
# --scraper-args "user password 1234567" causing that account to be selected
# before scraping the statement
#
class ItauUYScraper < BaseScraper
  MONTHS_IN_SPANISH = %w(ENE FEB MAR ABR MAY JUN JUL AGO SET OCT NOV DIC).freeze

  currency  "USD" # Set the default currency as dollars
  decimal   "."    # Itau UY statements use commas as separators but we convert them to periods anyway
  account_number "1234567" # override this with a real account number
  account_type Statement::CHECKING # this is the default anyway

  # This rule detects checque payments and modifies the description
  # and sets the type
  transaction_rule do |tx|
    if tx.raw_description =~ /CHEQUE\s+(\d+)/i
      cheque_number = $1
      # change the description but append $' in case there was trailing text after the cheque no
      tx.description = "Cheque ##{cheque_number} withdrawn #{$'}"
      tx.type = Transaction::CHECK
      tx.check_number = cheque_number
    end
  end

  # This rule detects transfers debits and modifies the description
  # and sets the type
  transaction_rule do |tx|
    if tx.raw_description =~ /TRASPASO A\s+(\d+)(ilink|mtpay)?/i
      acct_number = $1
      # change the description but append $' in case there was trailing text after the cheque no
      tx.description = "Transfer to #{acct_number} #{$2}#{$'}"
      tx.type = Transaction::XFER
    end
  end

  # This rule detects transfers credits and modifies the description
  # and sets the type
  transaction_rule do |tx|
    if tx.raw_description =~ /TRASPASO DE\s+(\d+)(ilink|mtpay)?/i
      acct_number = $1
      # change the description but append $' in case there was trailing text after the cheque no
      tx.description = "Transfer from #{acct_number} #{$2}#{$'}"
      tx.type = Transaction::XFER
    end
  end

  # Some constants for the URLs and main elements in the Itau UY bank app
  LOGIN_URL = 'https://www.itaulink.com.uy'

  def named_args
    @named_args ||= {"config" => "~/.bankjob.yml", "env" => "default"}.tap do |h|
      scraper_args.each do |pair|
        k, v = pair.split(':')
        h[k] = v
      end
    end
  end

  def args
    @args ||= load_args
  end

  def load_args
    config = Pathname.new(named_args['config']).expand_path
    if config.file?
      logger.info "Loading config from #{config} for environment '#{named_args['env']}'"
      YAML.load_file(config).fetch(named_args['env']).merge(named_args)
    else
      named_args
    end
  end

  ##
  # Uses the mechanize web +agent+ to fetch the page holding the most recent
  # bank transactions and returns it.
  # This overrides (implements) +fetch_transactions_page+ in BaseScraper
  #
  def fetch_transactions_page(agent)
    # Current month
    #transactions_url = "https://www.itaulink.com.uy/appl/servlet/FeaServlet?id=estado_cuenta&nro_cuenta=#{args['account']}&tipo_cuenta=0&cod_moneda=US.D"

    # Previous month (072011)
    #transactions_url = "https://www.itaulink.com.uy/appl/servlet/FeaServlet?consulta=2&dias=10&mes_anio=072011&numero=&dia=&mes=&anio=&id=estado_cuenta_avanzado&bajar_archivo=N&nro_cuenta=#{args['account']}&cod_moneda=US.D&tipo_cuenta=0&Submit=Enviar&fecha="

    # Last 10 days
    transactions_url = "https://www.itaulink.com.uy/appl/servlet/FeaServlet?consulta=1&dias=10&mes_anio=102010&numero=&dia=&mes=&anio=&id=estado_cuenta_avanzado&bajar_archivo=N&nro_cuenta=#{args['account']}&cod_moneda=US.D&tipo_cuenta=0&Submit=Enviar&fecha="

    login(agent)
    logger.info("Logged in, now navigating to transactions on #{transactions_url}.")
    transactions_page = agent.get(transactions_url)
    if (transactions_page.nil?)
      raise "Itau UY Scraper failed to load the transactions page at #{transactions_url}"
    end

    return transactions_page
  end

  def date_from_spanish(date_str) # example input: 20ENE2010
    day   = date_str[0, 2].to_i
    month = date_str[2, 3]
    year  = date_str[5, 4].to_i
    Time.local(year, MONTHS_IN_SPANISH.index(month) + 1, day)
  end

  ##
  # Parses the Itau UY page listing about a weeks worth of transactions
  # and creates a Transaction for each one, putting them together
  # in a Statement.
  # Overrides (implements) +parse_transactions_page+ in BaseScraper.
  #
  def parse_transactions_page(transactions_page)
    begin
      statement = create_statement

      account_number = get_account_number(transactions_page)
      statement.account_number = account_number unless account_number.nil?

      # each row with the bgcolor attribute set to "#FDF2D0" holds a transaction, except for
      # the first and last ones which hold initial and final balances. We ignore them.
      rows = transactions_page.search("tr[@bgcolor='#FDF2D0']")[1..-2]
      rows.each do |row|
        transaction = create_transaction # use the support method because it sets the separator

        # collect all of the table cells' inner text in an array (stripping leading/trailing spaces)
        data = row.search("td").collect{ |cell| cell.content.gsub("\302\240","").strip }

        # the first (0th) column holds the date
        transaction.date = date_from_spanish(data[0])

        # the transaction raw_description is in the 2nd column
        transaction.raw_description = data[1].gsub(/\s+/, ' ')

        # the 3th column holds the debit transaction amount (with comma as decimal place)
        # the 4th column holds the credit transaction amount (with comma as decimal place)
        amount = "-" + data[2]            # asume debit
        amount = data[3] if amount == "-" # change to credit if needed
        transaction.amount = amount.tr('.', '').tr(',', '.')

        # the new balance is in the last column
        transaction.new_balance = data[4].tr('.', '').tr(',', '.')

        # add the new transaction to the array
        statement.add_transaction(transaction)
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
    # and to fake the times since the Itau UY web pages
    # don't hold the transaction times
    statement.finish_with_most_recent_last(true) # fake_times

    return statement
  end

  def get_account_number(transactions_page)
    element = transactions_page.search("td[class='Texto_bold_grande']").detect {|elem| elem.content =~ /en.+número.+?(\d+)/ }
    account_number = element.content.match(/en.+número.+?(\d+)/)[1]
    return account_number
  end

  ##
  # Logs into the Itau UY banking app by finding the form
  # setting the name and password and submitting it then
  # waits a bit.
  #
  def login(agent)
    logger.info("Logging in to #{LOGIN_URL}.")

    self.class.currency args['currency']

    # Important to get the session cookie.
    page = agent.get("#{LOGIN_URL}/index.jsp")

    # navigate to the login page
    login_page = agent.get("#{LOGIN_URL}/appl/index.jsp")

    # find login form - it's called 'form1' - fill it out and submit it
    form  = login_page.form('form1')

    if args["tipo"].downcase == "empresa"
      rb_value = "C" # empresa
    else
      rb_value = "R" # persona
    end

    form.radiobuttons_with(:name => "tipo_usuario").each do |rb|
      rb.checked = rb.value == rb_value
    end

    if args["tipo"].downcase == "empresa"
      form.empresa_aux = args['empresa']
      form.pwd_empresa = args['pwd_empresa']
      form.usuario_aux = args['usuario']
      form.pwd_usuario = args['pwd_usuario']

      # Hidden fields are assigned by javascript but we do it here.
      form.empresa = form.empresa_aux.upcase
      form.usuario = form.usuario_aux.downcase
    else
      form.tipo_documento = "1" # Cédula de identidad
      form.nro_documento = args['usuario']
      form.password = args['password']
    end

    # submit the form - same as the user hitting the Login button
    agent.submit(form)
    sleep 3  # wait while the login takes effect
  end
end # class ItauUYScraper
