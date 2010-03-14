require 'builder'

module Bankjob
  class OutputFormatter
    class OfxFormatter
      attr_accessor :destination

      def initialize(destination)
        @destination = destination.blank? ? STDOUT : destination
      end

      def output(statement)
        output_to(destination) do |ofx|
          ofx.hello("test")
          # csv << [ "Account Number",  statement.account_number ]
          # csv << [ "Bank ID",         statement.bank_id ]
          # csv << [ "Account Type",    statement.account_type ]
          # csv << [ "Closing balance", statement.closing_balance ]
          # csv << [ "Available funds", statement.closing_available ]
          # csv << [ "Currency",        statement.currency ]
          # csv << []
          # transactions = statement.transactions.sort_by { |tx| tx.date }
          # transactions.each do |transaction|
          #   information = []
          #   information << transaction.date.strftime("%Y-%m-%d")
          #   information << transaction.type
          #   information << transaction.description
          #   information << transaction.amount
          #   csv << information
          # end
        end
      end

      private
      def output_to(destination, &block)
        case destination
        when String
          builder = Builder::XmlMarkup.new(:indent => 2)
          ofx = yield builder
          File.open(destination, 'w') { |f| f.puts ofx }
        when IO
          yield Builder::XmlMarkup.new(:target => destination,
                                       :indent => 2)
        end
      end
    end
  end
end