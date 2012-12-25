require 'rubygems'
require 'digest/md5'
require 'bankjob'

module Bankjob

  ##
  # A Transaction object represents a transaction in a bank account (a withdrawal, deposit,
  # transfer, etc) and is generally the result of running a Bankjob scraper.
  #
  # A Scraper will create Transactions while scraping web pages in an online banking site.
  # These Transactions will be collected in a Statement object which will then be written
  # to a file.
  #
  class Transaction

    # OFX transaction type for Generic credit
    CREDIT      = "CREDIT"

    # OFX transaction type for Generic debit
    DEBIT       = "DEBIT"

    # OFX transaction type for Interest earned or paid. (Depends on signage of amount)
    INT         = "INT"

    # OFX transaction type for Dividend
    DIV         = "DIV"

    # OFX transaction type for FI fee
    FEE         = "FEE"

    # OFX transaction type for Service charge
    SRVCHG      = "SRVCHG"

    # OFX transaction type for Deposit
    DEP         = "DEP"

    # OFX transaction type for ATM debit or credit. (Depends on signage of amount)
    ATM         = "ATM"

    # OFX transaction type for Point of sale debit or credit. (Depends on signage of amount)
    POS         = "POS"

    # OFX transaction type for Transfer
    XFER        = "XFER"

    # OFX transaction type for Check
    CHECK       = "CHECK"

    # OFX transaction type for Electronic payment
    PAYMENT     = "PAYMENT"

    # OFX transaction type for Cash withdrawal
    CASH        = "CASH"

    # OFX transaction type for Direct deposit
    DIRECTDEP   = "DIRECTDEP"

    # OFX transaction type for Merchant initiated debit
    DIRECTDEBIT = "DIRECTDEBIT"

    # OFX transaction type for Repeating payment/standing order
    REPEATPMT   = "REPEATPMT"

    # OFX transaction type for Other
    OTHER       = "OTHER"

    # OFX type of the transaction (credit, debit, atm withdrawal, etc)
    # Translates to the OFX element TRNTYPE and according to the OFX 2.0.3 schema this can be one of
    # * CREDIT
    # * DEBIT
    # * INT
    # * DIV
    # * FEE
    # * SRVCHG
    # * DEP
    # * ATM
    # * POS
    # * XFER
    # * CHECK
    # * PAYMENT
    # * CASH
    # * DIRECTDEP
    # * DIRECTDEBIT
    # * REPEATPMT
    # * OTHER
    attr_accessor :type

    # date of the transaction
    # Translates to OFX element DTPOSTED
    attr_accessor :date

    # the date the value affects the account (e.g. funds become available)
    # Translates to OFX element DTUSER
    attr_accessor :value_date

    # description of the transaction
    # This description is typically set by taking the raw description and
    # applying rules. If it is not set explicitly it returns the same
    # value as +raw_description+
    # Translates to OFX element MEMO
    attr_accessor :description

    # the original format of the description as scraped from the bank site
    # This allows the raw information to be preserved when modifying the
    # +description+ with transaction rules (see Scraper#transaction_rule)
    # This does _not_ appear in the OFX output, only +description+ does.
    attr_accessor :raw_description

    # amount of the credit or debit (negative for debits)
    # Translates to OFX element TRNAMT
    attr_accessor :amount

    # account balance after the transaction
    # Not used in OFX but important for working out statement balances
    attr_accessor :new_balance

    # account balance after the transaction as a numeric Ruby Float
    # Not used in OFX but important for working out statement balances
    # in calculations (see #real_amount)
    attr_reader :real_new_balance

    # the generated unique id for this transaction in an OFX record
    # Translates to OFX element FITID this is generated if not set
    attr_accessor :ofx_id

    # the payee of an expenditure (ie a debit or transfer)
    # This is of type Payee and translates to complex OFX element PAYEE
    attr_accessor :payee

    # the cheque number of a cheque transaction
    # This is of type Payee and translates to OFX element CHECKNUM
    attr_accessor :check_number

    ##
    # the numeric real-number amount of the transaction.
    #
    # The transaction amount is typically a string and may hold commas for
    # 1000s or for decimal separators, making it unusable for mathematical
    # operations.
    #
    # This attribute returns the amount converted to a Ruby Float, which can
    # be used in operations like:
    # <tt>
    #   if (transaction.real_amount < 0)
    #     puts "It's a debit!"
    #   end
    #
    # The +real_amount+ attribute is calculated using the +decimal+ separator
    # passed into the constructor (defaults to ".")
    # See Scraper#decimal
    #
    # This attribute is not used in OFX.
    #
    attr_reader :real_amount

    ##
    # Creates a new Transaction with the specified attributes.
    #
    def initialize(decimal = ".")
      @ofx_id = nil
      @date = nil
      @value_date = nil
      @raw_description = nil
      @description = nil
      @amount = 0
      @new_balance = 0
      @decimal = decimal

      # Always create a Payee even if it doesn't get used - this ensures an empty
      # <PAYEE> element in the OFX output which is more correct and, for one thing,
      # stops Wesabe from adding UNKNOWN PAYEE to every transaction (even deposits)
      @payee = Payee.new()
      @check_number = nil
      @type = OTHER
    end
   
    def date=(raw_date_time)
      @date = Bankjob.create_date_time(raw_date_time)
    end

    def value_date=(raw_date_time)
      @value_date = Bankjob.create_date_time(raw_date_time)
    end

    ##
    # Creates a unique ID for the transaction for use in OFX documents, unless
    # one has already been set.
    # All OFX transactions need a unique identifier.
    #
    # Note that this is generated by creating an MD5 digest of the transaction
    # date, raw description, type, amount and new_balance. Which means that two
    # identical transactions will always produce the same +ofx_id+.
    # (This is important so that repeated scrapes of the same transaction value
    #  produce identical ofx_id values)
    #
    def ofx_id() 
      if @ofx_id.nil?
        text = "#{@date}:#{@raw_description}:#{@type}:#{@amount}:#{@new_balance}"
        @ofx_id= Digest::MD5.hexdigest(text)
      end
      return @ofx_id
    end

    ##
    # Returns the description, defaulting to the +raw_description+ if no
    # specific description has been set by the user.
    #
    def description()
      @description.nil? ? raw_description : @description
    end

    ##
    # Returns the Transaction amount attribute as a ruby Float after 
    # replacing the decimal separator with a . and stripping any other
    # separators.
    #
    def real_amount()
      Bankjob.string_to_float(amount, @decimal)
    end

    ##
    # Returns the new balance after the transaction as a ruby Float after
    # replacing the decimal separator with a . and stripping any other
    # separators.
    #
    def real_new_balance()
      Bankjob.string_to_float(new_balance, @decimal)
    end

    ##
    # Produces a string representation of the transaction
    #
    def to_s
      "#{self.class} - ofx_id: #{@ofx_id}, date:#{@date}, raw description: #{@raw_description}, type: #{@type} amount: #{@amount}, new balance: #{@new_balance}"
    end

    ##
    # Overrides == to allow comparison of Transaction objects so that they can
    # be merged in Statements. See Statement#merge
    #
    def ==(other) #:nodoc:
      if other.kind_of?(Transaction)
        # sometimes the same date, when written and read back will not appear equal so convert to 
        # a canonical string first
        return (@date.strftime( '%Y%m%d%H%M%S' ) == other.date.strftime( '%Y%m%d%H%M%S' ) and
            # ignore value date - it may be updated between statements
            # (consider using ofx_id here later)
            @raw_description == other.raw_description and
            @amount == other.amount and
            @type == other.type and
            @new_balance == other.new_balance)
      end
    end

    #
    # Overrides eql? so that array union will work when merging statements
    #
    def eql?(other) #:nodoc:
      return self == other
    end

    ##
    # Overrides hash so that array union will work when merging statements
    #
    def hash() #:nodoc:
      prime = 31;
      result = 1;
      result = prime * result + @amount.to_i
      result = prime * result + @new_balance.to_i
      result = prime * result + (@date.nil? ? 0 : @date.strftime( '%Y%m%d%H%M%S' ).hash);
      result = prime * result + (@raw_description.nil? ? 0 : @raw_description.hash);
      result = prime * result + (@type.nil? ? 0 : @type.hash);
      # don't use value date
      return result;
    end

  end # class Transaction
end # module

