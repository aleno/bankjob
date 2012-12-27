require 'rubygems'
require 'bankjob'

module Bankjob

  ##
  # A Statement object represents a bank statement and is generally the result of running a Bankjob scraper.
  # The Statement holds an array of Transaction objects and specifies the closing balance and the currency in use.
  #
  # A Scraper will create a Statement by scraping web pages in an online banking site.
  #
  class Statement

    # OFX value for the ACCTTYPE of a checking account
    CHECKING   = "CHECKING"

    # OFX value for the ACCTTYPE of a savings account
    SAVINGS    = "SAVINGS"

    # OFX value for the ACCTTYPE of a money market account
    MONEYMRKT  = "MONEYMRKT"

    # OFX value for the ACCTTYPE of a loan account
    CREDITLINE = "CREDITLINE"

    # the account balance after the last transaction in the statement
    # Translates to the OFX element BALAMT in LEDGERBAL
    attr_accessor :closing_balance

    # the avaliable funds in the account after the last transaction in the statement (generally the same as closing_balance)
    # Translates to the OFX element BALAMT in AVAILBAL
    attr_accessor :closing_available

    # the array of Transaction objects that comprise the statement
    attr_accessor :transactions

    # the three-letter currency symbol generated into the OFX output (defaults to EUR)
    # This is passed into the initializer (usually by the Scraper - see Scraper#currency)
    attr_reader :currency 

    # the identifier of the bank - a 1-9 char string (may be empty)
    # Translates to the OFX element BANKID
    attr_accessor :bank_id

    # the account number of the statement - a 1-22 char string that must be passed
    # into the initalizer of the Statement
    # Translates to the OFX element ACCTID
    attr_accessor :account_number

    # the type of bank account the statement is for
    # Tranlsates to the OFX type ACCTTYPE and must be one of
    # * CHECKING
    # * SAVINGS
    # * MONEYMRKT
    # * CREDITLINE
    # Use a constant to set this - defaults to CHECKING
    attr_accessor :account_type

    # the last date of the period the statement covers
    # Translates to the OFX element DTEND
    attr_writer :to_date
    def to_date
      @to_date || transactions.sort_by { |tx| tx.date }[0].date
    end

    # the first date of the period the statement covers
    # Translates to the OFX element DTSTART
    attr_writer :from_date
    def from_date
      @from_date || transactions.sort_by { |tx| tx.date }[-1].date
    end

    ##
    # Creates a new empty Statement with no transactions.
    # The +account_number+ must be specified as a 1-22 character string.
    # The specified +currency+ defaults to EUR if nothing is passed in.
    #
    def initialize(account_number, currency = "EUR")
      @account_number = account_number
      @currency = currency
      @transactions = []
      @account_type = CHECKING
      @closing_balance = nil
      @closing_available = nil
    end
    
    ##
    # Appends a new Transaction to the end of this Statement
    #
    def add_transaction(transaction)
      @transactions << transaction
    end

    ##
    # Overrides == to allow comparison of Statement objects.
    # Two Statements are considered equal (that is, ==) if
    # and only iff they have the same values for:
    # * +to_date+
    # * +from_date+
    # * +closing_balance+
    # * +closing_available+
    # * each and every transaction.
    # Note that the transactions are compared with Transaction.==
    #
    def ==(other) # :nodoc:
      if other.kind_of?(Statement) 
        return (from_date == other.from_date and
            to_date == other.to_date and
            closing_balance == other.closing_balance and
            closing_available == other.closing_available and
            transactions == other.transactions)
      end
      return false
    end
   
    ##
    # Merges the transactions of +other+ into the transactions of this statement
    # and returns the resulting array of transactions
    # Raises an exception if the two statements overlap in a discontiguous fashion.
    #
    def merge_transactions(other)
      if (other.kind_of?(Statement))
        union = transactions | other.transactions # the set union of both
        # now check that the union contains all of the originals, otherwise
        # we have merged some sort of non-contiguous range
        raise "Failed to merge transactions properly." unless union.last(other.transactions.length) == other.transactions
        return union
      end
    end

    ##
    # Merges the transactions of +other+ into the transactions of this statement
    # and returns the result.
    # Neither statement is changed. See #merge! if you want to modify the statement.
    # Raises an exception if the two statements overlap in a discontiguous fashion.
    #
    def merge(other)
      union = merge_transactions(other)
      merged = self.dup
      merged.closing_balance = nil
      merged.closing_available = nil
      merged.transactions = union
      return merged
    end

    ##
    # Merges the transactions of +other+ into the transactions of this statement.
    # Causes this statement to be changed. See #merge for details.
    #
    def merge!(other)
      @closing_balance = nil
      @closing_available = nil
      @transactions = merge_transactions(other)
    end
    
    ONE_MINUTE = 60
    ELEVEN_59_PM = 23 * 60 * 60 + 59 * 60  # seconds at 23:59
    MIDDAY = 12 * 60 * 60

    ##
    # Finishes the statement after scraping in two ways depending on the information
    # that the scraper was able to obtain. Optionally have your scraper class call
    # this after scraping is finished.
    #
    # This method:
    # 
    # 1. Sets the closing balance and available_balance and the to_ and from_dates
    #    by using the first and last transactions in the list. Which transaction is
    #    used depends on whether +most_recent_first+ is true or false.
    #    The scraper may just set these directly in which case this may not be necessary.
    #
    # 2. If +fake_times+ is true time-stamps are invented and added to the transaction
    #    date attributes. This is useful if the website beings scraped shows dates, but
    #    not times, but has transactions listed in chronoligical arder. 
    #    Without this process, the ofx generated has no proper no indication of the order of
    #    transactions that occurred in the same day other than the order in the statement
    #    and this may be ignored by the client. (Specifically, Wesabe will reorder transactions
    #    in the same day if they all appear to occur at the same time).
    #    
    #    Note that the algorithm to set the fake times is a little tricky. Assuming
    #    the transactionsa are most-recent-first, the first last transaction on each 
    #    day is set at 11:59pm each transaction prior to that is one minute earlier.
    #    
    #    But for the first transactions in the statement, the first is set at a few
    #    minutes after midnight, then we count backward. (The actual number of minutes
    #    is based on the number of transactions + 1 to be sure it doesnt pass midnight)
    #    
    #    This is crucial because transactions for a given day will often span 2 or more
    #    statement. By starting just after midnight and going back to just before midnight
    #    we reduce the chance of overlap.
    #
    #    If the to-date is the same as the from-date for a transaction, then we start at
    #    midday, so that prior and subsequent statements don't overlap.
    #
    #   This simple algorithm basically guarantees no overlaps so long as:
    #   i.  The number of transactions is small compared to the number of minutes in a day
    #   ii. A single day will not span more than 3 statements
    #
    #   If the statement is most-recent-last (+most_recent_first = false+) the same
    #   algorithm is applied, only in reverse
    #
    def finish(most_recent_first, fake_times=false)
      if !@transactions.empty? then
        # if the user hasn't set the balances, set them to the first or last
        # transaction balance depending on the order
        if most_recent_first then
          @closing_balance ||= transactions.first.new_balance
          @closing_available ||= transactions.first.new_balance
          @to_date ||= transactions.first.date
          @from_date ||= transactions.last.date
        else
          @closing_balance ||= transactions.last.new_balance
          @closing_available ||= transactions.last.new_balance
          @to_date ||= transactions.last.date
          @from_date ||= transactions.first.date
        end

        if fake_times and to_date.hour == 0 then
          # the statement was unable to scrape times to go with the dates, but the
          # client (say wesabe) will get the transaction order wrong if there are no
          # times, so here we add times that order the transactions according to the
          # order of the array of transactions

          # the delta is 1 minute forward or backward fr
          if to_date == from_date then
            # all of the statement's transactions occur in the same day - to try to
            # avoid overlap with subsequent or previous transacitons we group order them
            # from 11am onward
            seconds = MIDDAY
          else
            seconds = (transactions.length + 1) * 60
          end

          if most_recent_first then
            yday = transactions.first.date.yday
            start = 0
            delta = 1
            finish = transactions.length
          else
            yday = transactions.last.date.yday
            start = transactions.length - 1
            finish = -1
            delta = -1
          end

          i = start
          until i == finish
            tx = transactions[i]
            if tx.date.yday != yday
              # starting a new day, begin the countdown from 23:59 again
              yday = tx.date.yday
              seconds = ELEVEN_59_PM
            end
            tx.date += seconds unless tx.date.hour > 0
            seconds -= ONE_MINUTE
            i += delta
          end
        end
      end
    end

    def finish_with_most_recent_last(fake_times = false)
      unless @transactions.empty?
        @closing_balance    ||= transactions.last.real_new_balance
        @closing_available  ||= transactions.last.real_new_balance
        @to_date            ||= transactions.last.date
        @from_date          ||= transactions.first.date

        start_time = 2 * 60 * 60 # 2 AM
        @transactions.group_by {|tx| tx.date }.each do |date, txs|
          txs.each_with_index do |tx, i|
            tx.date += start_time + i * ONE_MINUTE
          end
        end
      end
    end

    def to_s
      buf = "#{self.class}: close_bal = #{closing_balance}, avail = #{closing_available}, curr = #{currency}, transactions:"
      transactions.each do |tx|
        buf << "\n\t\t#{tx.to_s}"
      end
      buf << "\n---\n"
      return buf
    end
  end # class Statement
end # module
