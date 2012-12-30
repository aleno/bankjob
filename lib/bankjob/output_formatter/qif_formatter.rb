module Bankjob
  class OutputFormatter
    class QifFormatter
      # FIXME: I shouldn't need to define this if I'm not interested in
      #        the arguments.
      def initialize(*args)
      end
      
      def output(statement)
        p "Account Number : #{statement.account_number}"
        p "Bank ID        : #{statement.bank_id}"
        p "Account Type   : #{statement.account_type}"
        p "Closing balance: #{statement.closing_balance}"
        p "Available funds: #{statement.closing_available}"
        p "Currency       : #{statement.currency}"
        p
        p "!Type:Bank"
        transactions = statement.transactions.sort_by { |tx| tx.date }
        transactions.each do |transaction|
          p transaction.date.strftime("D%m/%d/%Y")
          p "T" + transaction.real_amount.to_s
          p "P" + transaction.description
          p "^"
        end
      end

      private
      def p(*args)
        STDOUT.puts *args
      end
    end
  end
end
