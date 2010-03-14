$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'bankjob/support'
require 'bankjob/statement'
require 'bankjob/transaction'
require 'bankjob/scraper'
require 'bankjob/payee'
require 'bankjob/output_formatter'

module Bankjob
  BANKJOB_VERSION = '0.5.2' unless defined?(BANKJOB_VERSION)
end
