module AccountInfos
  def initialize_account_infos continously: false
    


	end  # def
=begin
Query's the tws for Account- and PortfolioValues
The parameter can either be the account_id, the IB::Account-Object or 
an Array of account_id and IB::Account-Objects.

returns the thread waiting for completing the request


call it via

	G.get_account_data.join 

for sequencial processing
=end
	def get_account_data *accounts
		logger.progname = 'Gateway#get_account_data'
		
		subscribe_id = tws.subscribe( :AccountValue, :PortfolioValue,:AccountDownloadEnd )  do | msg |

			for_selected_account( msg.account_name ) do | account |
				case msg
				when IB::Messages::Incoming::AccountValue
					# debugging:  puts "#{account.account} => AccountValue "
					account.account_values.update_or_create msg.account_value, :currency, :key
					account.update_attribute :last_updated, Time.now
				when IB::Messages::Incoming::AccountDownloadEnd
					account.update_attribute :connected, true   ## flag: Account is completely initialized
					logger.info{ "#{account.account} => Count of AccountValues: #{account.account_values.size} "  }
					send_message :RequestAccountData, subscribe: false, account_code: account.account

				when IB::Messages::Incoming::PortfolioValue
					account.contracts.update_or_create  msg.contract
					account.portfolio_values.update_or_create( msg.portfolio_value ){ :contract }
					msg.portfolio_value.account = account
					# link contract -> portfolio value
					account.contracts.find{|x| x.con_id == msg.contract.con_id}.portfolio_values << account.portfolio_values.find{|y| y == msg.portfolio_value}
				end # case
			end # for_selected_account 
		end # subscribe

		accounts =  active_accounts if accounts.empty?
		accounts.each do | ac |
			account =  ac.is_a?( IB::Account ) ?  ac  : active_accounts.find{|x| x.account == ac } 
			logger.info{ "#{account.account} :: Requesting AccountData " }
			account.update_attribute :connected, false  # indicates: AccountUpdate in Progress
			send_message :RequestAccountData, subscribe: true, account_code: account.account
				sleep 0.3  ## the delay is essential. Otherwise the requests are not processed correctly
		end

		Thread.new do 
			i =  0
			loop do
				break if accounts.map( &:connected ).all?( true  ) 
				i+=1
				sleep 0.2
				error "Account Infos not correctly processed. Please restart TWS/Gateway. 
				If this is not successful increase delay time in \'lib/ib/account_info.rb#49\'" if i > 10
			end 
			tws.unsubscribe subscribe_id
		end

	
	end


  def all_contracts
		active_accounts.map(&:contracts).flat_map(&:itself).uniq(&:con_id)
  end

end # module
