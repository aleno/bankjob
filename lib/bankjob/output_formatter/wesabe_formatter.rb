begin
  require 'wesabe'

  module Bankjob
    class OutputFormatter
      class WesabeFormatter
        attr_accessor :username, :password, :account_number

        def initialize(credentials)
          @username, @password, @account_number = credentials.to_s.split(/ /, 3)
          if @username.blank? || @password.blank?
            raise ArgumentError, "You must specify a username and password (and optionally a target account number) to use Wesabe."
          end
        end

        def output(statement)
          ofx_formatter = OfxFormatter.new
          ofx_formatter.destination = StringIO.new("", 'w+')
          ofx_formatter.output(statement)
          ofx_formatter.destination.rewind
          ofx = ofx_formatter.destination.read

          wesabe = Wesabe.new(username, password)
          accounts = wesabe.accounts

          # FIXME: All these puts lines should really go to a logger.
          if accounts.empty?
            puts "You should create a bank account at http://wesabe.com/ before using this plugin."
          elsif account_number && !accounts.any? { |account| account.id == account_number.to_i }
            puts "You asked to upload to account number #{account_number} but your accounts are numbered #{accounts.map{|a| a.id}.join(', ')}."
          elsif !account_number && accounts.length > 1
            puts "You didn't specify an account number to upload to but you have #{accounts.length} accounts."
          elsif account_number && account_number.to_i <= 0
            puts "The account number must be between 1 and #{accounts.length} but you asked me to upload to account number #{account_number.to_i}."
          else
            self.account_number ||= 1
            account = wesabe.account(account_number.to_i)
            uploader = account.new_upload
            uploader.statement = ofx
            uploader.upload!
          end
        end
      end
    end
  end
rescue LoadError => exception
  module Bankjob
    class OutputFormatter
      class WesabeFormatter
        def initialize(*args)
        end

        def output(statement)
            msg = "Failed to load the Wesabe gem. Did you install it?\n"
            msg << "\n"
            msg << "Install the gem by running this as the administrator user (usually root):\n"
            msg << "  gem install -r --source http://gems.github.com/ wesabe-wesabe"
            puts msg
        end
      end
    end
  end
end

