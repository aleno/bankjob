require 'csv'

module Bankjob
  class OutputFormatter
    class CsvFormatter
      attr_accessor :destination

      def initialize(destination)
        @destination = destination.to_s.empty? ? STDOUT : destination
      end

      def output(statement)
        output_to(destination) do |csv|
          csv << [ "Account Number",  statement.account_number ]
          csv << [ "Bank ID",         statement.bank_id ]
          csv << [ "Account Type",    statement.account_type ]
          csv << [ "Closing balance", statement.closing_balance ]
          csv << [ "Available funds", statement.closing_available ]
          csv << [ "Currency",        statement.currency ]
          csv << []
          transactions = statement.transactions.sort_by { |tx| tx.date }
          transactions.each do |transaction|
            information = []
            information << transaction.date.strftime("%Y-%m-%d")
            information << transaction.type
            information << transaction.description
            information << transaction.real_amount
            csv << information
          end
        end
      end

      private
      def output_to(destination, &block)
        case destination
        when String
          CSV.open(destination, 'w') { |csv| yield csv }
        when IO
          CSV(destination) { |csv| yield csv }
        end
      end
    end
  end
end
