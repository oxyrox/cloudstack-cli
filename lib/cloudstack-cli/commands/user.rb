class User < CloudstackCli::Base

  USER_TYPES = {
    0 => 'user',
    1 => 'domain-admin',
    2 => 'admin'
  }

  desc 'list', 'list users'
  option :listall
  option :account
  def list
    users = client.list_users(options)
    if users.size < 1
      say "No users found."
    else
      table = [["Account", "Type", "Name", "Email", "State", "Domain"]]
      users.each do |user|
        table << [
          user['account'], USER_TYPES[user['accounttype']], "#{user['firstname']} #{user['lastname']}",
          user['email'], user['state'], user['domain']
        ]
      end
      print_table table
      say "Total number of users: #{users.size}"
    end
  end
  
end