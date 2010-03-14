require 'rubygems'

module Bankjob

  ##
  # A Payee object represents an entity in a in a bank Transaction that receives a payment.
  #
  # A Scraper will create Payees while scraping web pages in an online banking site.
  # In many cases Payees will not be distinguished in the online bank site in which case
  # rules will have to be applied to separate the Payees
  #
  class Payee

    # name of the payee
    # Translates to OFX element NAME
    attr_accessor :name

    # address of the payee
    # Translates to OFX element ADDR1
    #-- TODO Consider ADDR2,3
    attr_accessor :address

    # city in which the payee is located
    # Translates to OFX element CITY
    attr_accessor :city

    # state in which the payee is located
    # Translates to OFX element STATE
    attr_accessor :state

    # post code or zip in which the payee is located
    # Translates to OFX element POSTALCODE
    attr_accessor :postalcode

    # country in which the payee is located
    # Translates to OFX element COUNTRY
    attr_accessor :country

    # phone number of the payee
    # Translates to OFX element PHONE
    attr_accessor :phone

    def to_s
      name
    end

  end # class Payee
end # module

