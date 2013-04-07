require 'rubygems'
require 'bankjob'      # this require will pull in all the classes we need
require 'base_scraper' # this defines scraper that BpiScraper extends

include Bankjob        # access the namespace of Bankjob

##
# BpiScraper is a scraper tailored to the mBank in Poland (www.mbank.com.pl).
#
class MbankScraper < BaseScraper

  currency "PLN"
  decimal ","
  account_number "12345678" # override this with a real account number
  account_type Statement::CHECKING # this is the default anyway

  def fetch_transactions_page(agent)
    csv = IO.read("./history.csv")
    csv_utf = csv.encode("UTF-8")
    FasterCSV.parse(csv_utf, :headers => true, :col_sep => ";")
  end

  def parse_transactions_page(page)
    statement = create_statement
    statement.account_number = 12345678

    page.each do |row|
      transaction = create_transaction

      transaction.type = Transaction::ATM

      transaction.date = row["#Data operacji"]

      transaction.value_date = row["#Data ksi\304\231gowania"]

      transaction.raw_description = row["#Opis operacji"]

      transaction.amount = row["#Kwota"]

      transaction.new_balance = row["#Saldo po operacji"]

      statement.add_transaction(transaction)
    end

    statement.finish(true, true) # most_recent_first, fake_times

    statement
  end

end
