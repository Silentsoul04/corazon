module Msf::DBManager::Host
  # Deletes a host and associated data matching this address/comm
  def del_host(wspace, address, comm='')
  ::ActiveRecord::Base.connection_pool.with_connection {
    address, scope = address.split('%', 2)
    host = wspace.hosts.find_by_address_and_comm(address, comm)
    host.destroy if host
  }
  end

  #
  # Iterates over the hosts table calling the supplied block with the host
  # instance of each entry.
  #
  def each_host(wspace=workspace, &block)
  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace.hosts.each do |host|
      block.call(host)
    end
  }
  end

  # Exactly like report_host but waits for the database to create a host and returns it.
  def find_or_create_host(opts)
    report_host(opts)
  end

  #
  # Find a host.  Performs no database writes.
  #
  def get_host(opts)
    if opts.kind_of? ::Mdm::Host
      return opts
    elsif opts.kind_of? String
      raise RuntimeError, "This invokation of get_host is no longer supported: #{caller}"
    else
      address = opts[:addr] || opts[:address] || opts[:host] || return
      return address if address.kind_of? ::Mdm::Host
    end
  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    address = normalize_host(address)
    return wspace.hosts.find_by_address(address)
  }
  end

  # Look for an address across all comms
  def has_host?(wspace,addr)
  ::ActiveRecord::Base.connection_pool.with_connection {
    address, scope = addr.split('%', 2)
    wspace.hosts.find_by_address(addr)
  }
  end

  # Returns a list of all hosts in the database
  def hosts(wspace = workspace, only_up = false, addresses = nil)
  ::ActiveRecord::Base.connection_pool.with_connection {
    conditions = {}
    conditions[:state] = [Msf::HostState::Alive, Msf::HostState::Unknown] if only_up
    conditions[:address] = addresses if addresses
    wspace.hosts.where(conditions).order(:address)
  }
  end

  #
  # Returns something suitable for the +:host+ parameter to the various report_* methods
  #
  # Takes a Host object, a Session object, an Msf::Session object or a String
  # address
  #
  def normalize_host(host)
    return host if defined?(::Mdm) && host.kind_of?(::Mdm::Host)
    norm_host = nil

    if (host.kind_of? String)

      if Rex::Socket.is_ipv4?(host)
        # If it's an IPv4 addr with a port on the end, strip the port
        if host =~ /((\d{1,3}\.){3}\d{1,3}):\d+/
          norm_host = $1
        else
          norm_host = host
        end
      elsif Rex::Socket.is_ipv6?(host)
        # If it's an IPv6 addr, drop the scope
        address, scope = host.split('%', 2)
        norm_host = address
      else
        norm_host = Rex::Socket.getaddress(host, true)
      end
    elsif defined?(::Mdm) && host.kind_of?(::Mdm::Session)
      norm_host = host.host
    elsif host.respond_to?(:session_host)
      # Then it's an Msf::Session object
      norm_host = host.session_host
    end

    # If we got here and don't have a norm_host yet, it could be a
    # Msf::Session object with an empty or nil tunnel_host and tunnel_peer;
    # see if it has a socket and use its peerhost if so.
    if (
        norm_host.nil? &&
        host.respond_to?(:sock) &&
        host.sock.respond_to?(:peerhost) &&
        host.sock.peerhost.to_s.length > 0
      )
      norm_host = session.sock.peerhost
    end
    # If We got here and still don't have a real host, there's nothing left
    # to try, just log it and return what we were given
    if !norm_host
      dlog("Host could not be normalized: #{host.inspect}")
      norm_host = host
    end

    norm_host
  end

  def host_state_changed(host, ostate)
    begin
      framework.events.on_db_host_state(host, ostate)
    rescue ::Exception => e
      wlog("Exception in on_db_host_state event handler: #{e.class}: #{e}")
      wlog("Call Stack\n#{e.backtrace.join("\n")}")
    end
  end

  #
  # Report a host's attributes such as operating system and service pack
  #
  # The opts parameter MUST contain
  # +:host+::         -- the host's ip address
  #
  # The opts parameter can contain:
  # +:state+::        -- one of the Msf::HostState constants
  # +:os_name+::      -- something like "Windows", "Linux", or "Mac OS X"
  # +:os_flavor+::    -- something like "Enterprise", "Pro", or "Home"
  # +:os_sp+::        -- something like "SP2"
  # +:os_lang+::      -- something like "English", "French", or "en-US"
  # +:arch+::         -- one of the ARCH_* constants
  # +:mac+::          -- the host's MAC address
  # +:scope+::        -- interface identifier for link-local IPv6
  # +:virtual_host+:: -- the name of the virtualization software, eg "VMWare", "QEMU", "Xen", "Docker", etc.
  #
  def report_host(opts)

    return if !active
    addr = opts.delete(:host) || return

    # Sometimes a host setup through a pivot will see the address as "Remote Pipe"
    if addr.eql? "Remote Pipe"
      return
    end

  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    ret = { }

    if !addr.kind_of? ::Mdm::Host
      addr = normalize_host(addr)

      unless ipv46_validator(addr)
        raise ::ArgumentError, "Invalid IP address in report_host(): #{addr}"
      end

      if opts[:comm] and opts[:comm].length > 0
        host = wspace.hosts.where(address: addr, comm: opts[:comm]).first_or_initialize
      else
        host = wspace.hosts.where(address: addr).first_or_initialize
      end
    else
      host = addr
    end

    ostate = host.state

    # Truncate the info field at the maximum field length
    if opts[:info]
      opts[:info] = opts[:info][0,65535]
    end

    # Truncate the name field at the maximum field length
    if opts[:name]
      opts[:name] = opts[:name][0,255]
    end

    if opts[:os_name]
      os_name, os_flavor = split_windows_os_name(opts[:os_name])
      opts[:os_name] = os_name if os_name.present?
      if opts[:os_flavor].present?
        if os_flavor.present? # only prepend if there is a value that needs it
          opts[:os_flavor] = os_flavor + opts[:os_flavor]
        end
      else
        opts[:os_flavor] = os_flavor
      end
    end

    opts.each do |k,v|
      if (host.attribute_names.include?(k.to_s))
        unless host.attribute_locked?(k.to_s)
          host[k] = v.to_s.gsub(/[\x00-\x1f]/n, '')
        end
      elsif !v.blank?
        dlog("Unknown attribute for ::Mdm::Host: #{k}")
      end
    end
    host.info = host.info[0,::Mdm::Host.columns_hash["info"].limit] if host.info

    # Set default fields if needed
    host.state       = Msf::HostState::Alive if !host.state
    host.comm        = ''        if !host.comm
    host.workspace   = wspace    if !host.workspace

    begin
      framework.events.on_db_host(host) if host.new_record?
    rescue ::Exception => e
      wlog("Exception in on_db_host event handler: #{e.class}: #{e}")
      wlog("Call Stack\n#{e.backtrace.join("\n")}")
    end

    host_state_changed(host, ostate) if host.state != ostate

    if host.changed?
      msf_import_timestamps(opts,host)
      host.save!
    end

    if opts[:task]
      Mdm::TaskHost.create(
          :task => opts[:task],
          :host => host
      )
    end

    host
  }
  end

  def split_windows_os_name(os_name)
    return [] if os_name.nil?
    flavor_match = os_name.match(/Windows\s+(.*)/)
    return [] if flavor_match.nil?
    ["Windows", flavor_match.captures.first]
  end

  #
  # Update a host's attributes via semi-standardized sysinfo hash (Meterpreter)
  #
  # The opts parameter MUST contain the following entries
  # +:host+::           -- the host's ip address
  # +:info+::           -- the information hash
  # * 'Computer'        -- the host name
  # * 'OS'              -- the operating system string
  # * 'Architecture'    -- the hardware architecture
  # * 'System Language' -- the system language
  #
  # The opts parameter can contain:
  # +:workspace+::      -- the workspace for this host
  #
  def update_host_via_sysinfo(opts)

    return if !active
    addr = opts.delete(:host) || return
    info = opts.delete(:info) || return

    # Sometimes a host setup through a pivot will see the address as "Remote Pipe"
    if addr.eql? "Remote Pipe"
      return
    end

  ::ActiveRecord::Base.connection_pool.with_connection {
    wspace = opts.delete(:workspace) || workspace
    if wspace.kind_of? String
      wspace = find_workspace(wspace)
    end

    if !addr.kind_of? ::Mdm::Host
      addr = normalize_host(addr)
      addr, scope = addr.split('%', 2)
      opts[:scope] = scope if scope

      unless ipv46_validator(addr)
        raise ::ArgumentError, "Invalid IP address in report_host(): #{addr}"
      end

      if opts[:comm] and opts[:comm].length > 0
        host = wspace.hosts.where(address: addr, comm: opts[:comm]).first_or_initialize
      else
        host = wspace.hosts.where(address: addr).first_or_initialize
      end
    else
      host = addr
    end

    ostate = host.state

    res = {}

    if info['Computer']
      res[:name] = info['Computer']
    end

    if info['Architecture']
      res[:arch] = info['Architecture'].split(/\s+/).first
    end

    if info['OS'] =~ /^Windows\s*([^\(]+)\(([^\)]+)\)/i
      res[:os_name]   = "Windows"
      res[:os_flavor] = $1.strip
      build = $2.strip

      if build =~ /Service Pack (\d+)/
        res[:os_sp] = "SP" + $1
      end
    end

    if info["System Language"]
      case info["System Language"]
        when /^en_/
          res[:os_lang] = "English"
      end
    end


    # Truncate the info field at the maximum field length
    if res[:info]
      res[:info] = res[:info][0,65535]
    end

    # Truncate the name field at the maximum field length
    if res[:name]
      res[:name] = res[:name][0,255]
    end

    res.each do |k,v|
      if (host.attribute_names.include?(k.to_s))
        unless host.attribute_locked?(k.to_s)
          host[k] = v.to_s.gsub(/[\x00-\x1f]/n, '')
        end
      elsif !v.blank?
        dlog("Unknown attribute for Host: #{k}")
      end
    end

    # Set default fields if needed
    host.state       = Msf::HostState::Alive if !host.state
    host.comm        = ''        if !host.comm
    host.workspace   = wspace    if !host.workspace

    host.save! if host.changed?
    host_state_changed(host, ostate) if host.state != ostate

    host
  }
  end
end
