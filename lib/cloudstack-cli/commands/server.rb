class Server < CloudstackCli::Base

  desc "list", "list servers"
  option :account, desc: "name of the account"
  option :project, desc: "name of the project"
  option :zone, desc: "the name of the availability zone"
  option :state, desc: "state of the virtual machine"
  option :listall, desc: "list all servers"
  option :storage_id, desc: "the storage ID where vm's volumes belong to"
  option :keyword, desc: "filter by keyword"
  option :command,
    desc: "command to execute for the given servers",
    enum: %w(START STOP REBOOT)
  option :concurrency, type: :numeric, default: 10, aliases: '-C',
    desc: "number of concurrent command to execute"
  option :format, default: "table",
    enum: %w(table json yaml)
  def list
    if options[:project]
      options[:project_id] = find_project['id']
      options[:project] = nil
    end
    options[:custom] = { 'storageid' => options[:storage_id] } if options[:storage_id]
    client.verbose = true
    servers = client.list_servers(options)
    if servers.size < 1
      puts "No servers found."
    else
      print_servers(servers)
      execute_server_commands(servers) if options[:command]
    end
  end

  desc "list_from_file FILE", "list servers from file"
  option :command,
  desc: "command to execute for the given servers",
  enum: %w(START STOP REBOOT)
  option :concurrency, type: :numeric, default: 10, aliases: '-C',
  desc: "number of concurrent command to execute"
  option :format, default: :table, enum: %w(table json yaml)
  def list_from_file(file)
    servers = parse_file(file)["servers"]
    if servers.size < 1
      puts "No servers found."
    else
      print_servers(servers)
      execute_server_commands(servers) if options[:command]
    end
  end

  desc "show NAME", "show detailed infos about a server"
  option :project
  def show(name)
    options[:project_id] = find_project['id'] if options[:project]
    unless server = client.get_server(name, options)
      puts "No server found."
    else
      table = server.map do |key, value|
        [ set_color("#{key}:", :yellow), "#{value}" ]
      end
      print_table table
    end
  end

  desc "create NAME [NAME2 ...]", "create server(s)"
  option :template, aliases: '-t', desc: "name of the template"
  option :iso, desc: "name of the iso", desc: "name of the iso template"
  option :offering, aliases: '-o', required: true, desc: "computing offering name"
  option :zone, aliases: '-z', required: true, desc: "availability zone name"
  option :networks, aliases: '-n', type: :array, desc: "network names"
  option :project, aliases: '-p', desc: "project name"
  option :port_rules, aliases: '-pr', type: :array,
    default: [],
    desc: "Port Forwarding Rules [public_ip]:port ..."
  option :disk_offering, desc: "disk offering (data disk for template, root disk for iso)"
  option :disk_size, desc: "disk size in GB"
  option :hypervisor, desc: "only used for iso deployments, default: vmware"
  option :keypair, desc: "the name of the ssh keypair to use"
  option :group, desc: "group name"
  option :account, desc: "account name"
  def create(*names)
    projectid = find_project['id'] if options[:project]
    say "Start deploying servers...", :green
    jobs = names.map do |name|
      server = client(quiet: true).get_server(name, project_id: projectid)
      if server
        say "Server #{name} (#{server["state"]}) already exists.", :yellow
        job = {
          id: 0,
          name: "Create server #{name}",
          status: 1
        }
      else
        job = {
          id: client.create_server(options.merge({name: name, sync: true}))['jobid'],
          name: "Create server #{name}"
        }
      end
      job
    end
    watch_jobs(jobs)
    if options[:port_rules].size > 0
      say "Create port forwarding rules...", :green
      jobs = []
      names.each do |name|
        server = client(quiet: true).get_server(name, project_id: projectid)
        create_port_rules(server, options[:port_rules], false).each_with_index do |job_id, index|
          jobs << {
            id: job_id,
            name: "Create port forwarding ##{index + 1} rules for server #{server['name']}"
          }
        end
      end
      watch_jobs(jobs)
    end
    say "Finished.", :green
  end

  desc "destroy NAME [NAME2 ..]", "destroy server(s)"
  option :project
  option :force, desc: "destroy without asking", type: :boolean, aliases: '-f'
  option :expunge, desc: "expunge server immediately", type: :boolean, default: false, aliases: '-E'
  def destroy(*names)
    projectid = find_project['id'] if options[:project]
    names.each do |name|
      server = client.get_server(name, project_id: projectid)
      unless server
        say "Server #{name} not found.", :red
      else
        ask = "Destroy #{name} (#{server['state']})? [y/N]:"
        if options[:force] || yes?(ask, :yellow)
          say "destroying #{name} "
          client.destroy_server(
            server["id"], {
              sync: false,
              expunge: options[:expunge]
            }
          )
          puts
        end
      end
    end
  end

  desc "bootstrap", "interactive creation of a server with network access"
  def bootstrap
    bootstrap_server_interactive
  end

  desc "stop NAME", "stop a server"
  option :project
  option :account
  option :force
  def stop(name)
    options[:project_id] = find_project['id'] if options[:project]
    exit unless options[:force] || yes?("Stop server #{name}? [y/N]:", :magenta)
    client.stop_server(name, options)
    puts
  end

  desc "start NAME", "start a server"
  option :project
  option :account
  def start(name)
    options[:project_id] = find_project['id'] if options[:project]
    say("Starting server #{name}", :magenta)
    client.start_server(name, options)
    puts
  end

  desc "reboot NAME", "reboot a server"
  option :project
  option :account
  option :force
  def reboot(name)
    options[:project_id] = find_project['id'] if options[:project]
    exit unless options[:force] || yes?("Reboot server #{name}? [y/N]:", :magenta)
    client.reboot_server(name, options)
    puts
  end

  no_commands do

    def print_servers(servers)
      case options[:format].to_sym
      when :yaml
        puts({'servers' => servers}.to_yaml)
      when :json
        say JSON.pretty_generate(servers: servers)
      else
        table = [["Name", "State", "Offering", "Zone", options[:project_id] ? "Project" : "Account", "IP's"]]
        servers.each do |server|
          table << [
            server['name'],
            server['state'],
            server['serviceofferingname'],
            server['zonename'],
            options[:project_id] ? server['project'] : server['account'],
            server['nic'].map { |nic| nic['ipaddress']}.join(' ')
          ]
        end
        print_table table
        say "Total number of servers: #{servers.count}"
      end
    end

    def execute_server_commands(servers)
      command = options[:command].downcase
      unless %w(start stop reboot).include?(command)
        say "\nCommand #{options[:command]} not supported.", :red
        exit 1
      end
      exit unless yes?("\n#{command.capitalize} the server(s) above? [y/N]:", :magenta)
      servers.each_slice(options[:concurrency]) do | batch |
        jobs = batch.map do |server|
          args = { sync: true, account: server['account'] }
          args[:project_id] = server['projectid'] if server['projectid']
          {
            id: client.send("#{command}_server", server['name'], args)['jobid'],
            name: "#{command.capitalize} server #{server['name']}"
          }
        end
        puts
        watch_jobs(jobs)
      end
    end

  end # no_commands

end
