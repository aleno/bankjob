require 'builder'

module Bankjob
  class OutputFormatter
    class OfxFormatter
      attr_accessor :destination

      def initialize(destination = nil)
        @destination = destination.to_s.empty? ? STDOUT : destination
      end

      def output(statement)
        output_to(destination) do |ofx|
          ofx.instruct!
          # Normally I'd do this:
          #
          # ofx.instruct! :OFX, :OFXHEADER => 200, :SECURITY => "NONE",
          #               :OLDFILEUID => "NONE", :NEWFILEUID => "NONE",
          #               :VERSION => "200"
          #
          # trouble is, I can't guarantee the order that the attributes
          # will be output in and Wesabe can't seem to parse the file if
          # they're in an order different to the below.
          #
          ofx << '<?OFX OFXHEADER="200" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE" VERSION="200"?>'

          case statement.account_type
          when "CREDITLINE"
            creditline_render(statement, ofx)
          else
            default_render(statement, ofx)
          end
        end
      end

      private
      def creditline_render(statement, ofx)
        ofx.OFX {
          ofx.CREDITCARDMSGSRSV1 {
            ofx.CCSTMTTRNRS {
              ofx.CCSTMTRS {
                ofx.CURDEF statement.currency
                ofx.CCACCTFROM {
                  ofx.ACCTID statement.account_number
                }
                ofx.BANKTRANLIST {
                  ofx.DTSTART statement.from_date.strftime('%Y%m%d%H%M%S')
                  ofx.DTEND statement.to_date.strftime('%Y%m%d%H%M%S')
                  statement.transactions.each { |transaction|
                    ofx.STMTTRN {
                      ofx.TRNTYPE transaction.type
                      ofx.DTPOSTED transaction.date.strftime('%Y%m%d%H%M%S')
                      ofx.TRNAMT transaction.amount	#Amount of transaction [amount] can be , or . separated
                      ofx.FITID transaction.ofx_id
                      ofx.PAYEE {
                        ofx.NAME transaction.payee.name
                        ofx.ADDR1 transaction.payee.address
                        ofx.CITY transaction.payee.city
                        ofx.STATE transaction.payee.state
                        ofx.POSTALCODE transaction.payee.postalcode
                        ofx.COUNTRY transaction.payee.country unless transaction.payee.country.nil? # minOccurs="0" in schema (above)
                        ofx.PHONE transaction.payee.phone
                      }
                      ofx.MEMO transaction.description
                    }
                  }
                }
                ofx.LEDGERBAL {
                  ofx.BALAMT statement.closing_balance
                  ofx.DTASOF statement.to_date.strftime('%Y%m%d%H%M%S')
                }
                ofx.AVAILBAL {	# the final Available balance
                  ofx.BALAMT statement.closing_available
                  ofx.DTASOF statement.to_date.strftime('%Y%m%d%H%M%S')
                }
              }
            }
          }
        }        
      end

      def default_render(statement, ofx)
        ofx.OFX {
          ofx.BANKMSGSRSV1 { #Bank Message Response
            ofx.STMTTRNRS {	#Statement-transaction aggregate response
              ofx.STMTRS { #Statement response
                ofx.CURDEF statement.currency	#Currency
                ofx.BANKACCTFROM {
                  ofx.BANKID statement.bank_id # bank identifier
                  ofx.ACCTID statement.account_number
                  ofx.ACCTTYPE statement.account_type # acct type: checking/savings/...
                }
                ofx.BANKTRANLIST {	#Transactions
                  ofx.DTSTART statement.from_date.strftime('%Y%m%d%H%M%S')
                  ofx.DTEND statement.to_date.strftime('%Y%m%d%H%M%S')
                  statement.transactions.each { |transaction|
                    ofx.STMTTRN {	# transaction statement
                      ofx.TRNTYPE transaction.type
                      ofx.DTPOSTED transaction.date.strftime('%Y%m%d%H%M%S')	#Date transaction was posted to account, [datetime] yyyymmdd or yyyymmddhhmmss
                      ofx.TRNAMT transaction.amount	#Amount of transaction [amount] can be , or . separated
                      ofx.FITID transaction.ofx_id
                      ofx.CHECKNUM transaction.check_number unless transaction.check_number.nil?
                      ofx.PAYEE {
                        ofx.NAME transaction.payee.name
                        ofx.ADDR1 transaction.payee.address
                        ofx.CITY transaction.payee.city
                        ofx.STATE transaction.payee.state
                        ofx.POSTALCODE transaction.payee.postalcode
                        ofx.COUNTRY transaction.payee.country unless transaction.payee.country.nil? # minOccurs="0" in schema (above)
                        ofx.PHONE transaction.payee.phone
                      }
                      ofx.MEMO transaction.description
                    }
                  }
                }
                ofx.LEDGERBAL {	# the final balance at the end of the statement
                  ofx.BALAMT statement.closing_balance # balance amount
                  ofx.DTASOF statement.to_date.strftime('%Y%m%d%H%M%S')		# balance date
                }
                ofx.AVAILBAL {	# the final Available balance
                  ofx.BALAMT statement.closing_available
                  ofx.DTASOF statement.to_date.strftime('%Y%m%d%H%M%S')
                }
              }
            }
          }
        }
      end

      def output_to(destination, &block)
        case destination
        when String
          builder = Builder::XmlMarkup.new(:indent => 2)
          ofx = yield builder
          File.open(destination, 'w') { |f| f.puts ofx }
        when StringIO, IO
          builder = Builder::XmlMarkup.new(:target => destination,
          :indent => 2)
          yield builder
        end
      end
    end
  end
end