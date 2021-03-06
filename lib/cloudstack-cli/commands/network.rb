class Network < CloudstackCli::Base

  desc "list", "list networks"
  option :project, desc: 'the project name of the network'
  option :account, desc: 'the owner of the network'
  option :zone, desc: 'typehe name of the zone the network belongs to'
  option :type, desc: 'the type of the network'
  option :showid, type: :boolean, desc: 'show the network id'
  option :showvlan, type: :boolean, desc: 'show the VLAN'
  def list
    project = find_project if options[:project]
    if options[:zone]
      unless zone = client.get_zone(options[:zone])
        say "Zone '#{options[:zone]}' not found.", :red
        exit 1
      end
      zone_id = zone['id']
    end

    networks = []
    if project
      networks = client.list_networks(project_id: project['id'], zone_id: zone_id)
    elsif options[:account]
      networks = client.list_networks(account: options[:account], zone_id: zone_id)
    else
      networks = client.list_networks(zone_id: zone_id)
      networks += client.list_networks(project_id: -1, zone_id: zone_id)
    end

    if options[:type]
      networks = filter_by(networks, 'type', options[:type])
    end

    if networks.size < 1
      puts "No networks found."
    else
      table = [%w(Name Displaytext Account/Project Zone Domain State Type Offering)]
      table[0] << "ID" if options[:showid]
      table[0] << "VLAN" if options[:showvlan]
      networks.each do |network|
        table << [
          network["name"],
          network["displaytext"],
          network["account"] || network["project"],
          network["zonename"],
          network["domain"],
          network["state"],
          network["type"],
          network["networkofferingname"]
        ]
        table[-1] << network["id"] if options[:showid]
        table[-1] << network["vlan"] if options[:showvlan]
      end
      print_table table
      say "Total number of networks: #{networks.count}"
    end
  end

  desc "default", "get the default network"
  option :zone
  def default
    network = client.get_default_network(options[:zone])
    unless network
      puts "No default network found."
    else
      table = [["Name", "Displaytext", "Domain", "Zone"]]
      table[0] << "ID" if options[:showid]
        table << [
          network["name"],
          network["displaytext"],
          network["domain"],
          network["zonename"]
        ]
        table[-1] << network["id"] if options[:showid]
      print_table table
    end
  end

  desc "show NAME", "show detailed infos about a network"
  option :project
  def show(name)
    if options[:project]
      if options[:project].downcase == "all"
        options[:project_id] = -1
      else
        project = find_project
        options[:project_id] = project['id']
      end
    end
    unless server = client.get_network(name, options[:project_id])
      puts "No network found."
    else
      table = server.map do |key, value|
        [ set_color("#{key}:", :yellow), "#{value}" ]
      end
      print_table table
    end
  end

  desc "restart NAME", "restart network"
  option :cleanup, type: :boolean, default: true
  def restart(name)
    network = client.get_network(name)
    network = client.get_network(name, -1) unless network
    unless network
      say "Network #{name} not found."
      exit 1
    end
    if yes? "Restart network \"#{network['name']}\" (cleanup=#{options[:cleanup]})?"
      p client.restart_network(network['id'], options[:cleanup])
    end
  end

  desc "delete NAME", "delete network"
  def delete(name)
    network = client.get_network(name)
    network = client.get_network(name, -1) unless network
    unless network
      say "Network \"#{name}\" not found."
      exit 1
    end
    if yes? "Destroy network \"#{network['name']}\"?"
      p client.delete_network(network['id'])
    end
  end

end