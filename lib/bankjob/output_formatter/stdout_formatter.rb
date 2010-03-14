module Bankjob
  class OutputFormatter
    class StdoutFormatter
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
        transactions = statement.transactions.sort_by { |tx| tx.date }
        transactions.each do |transaction|
          information = []
          information << transaction.date.strftime("%Y-%m-%d")
          information << transaction.type
          information << transaction.description
          information << transaction.amount
          p "%-10.10s %-8.8s %-49.49s %10.10s" % information
        end
      end

      private
      def p(*args)
        STDOUT.puts *args
      end
    end
  end
end