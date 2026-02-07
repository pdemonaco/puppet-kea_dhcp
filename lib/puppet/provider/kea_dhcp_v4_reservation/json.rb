# frozen_string_literal: true

require 'puppet_x/kea_dhcp/provider/dhcp4_json'

Puppet::Type.type(:kea_dhcp_v4_reservation).provide(:json, parent: PuppetX::KeaDhcp::Provider::Dhcp4Json) do
  desc 'Manages Kea DHCPv4 host reservations stored in the kea-dhcp4 JSON configuration.'

  require 'ipaddr'

  RESERVATIONS_KEY = 'reservations'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    config = config_for(self::DEFAULT_CONFIG_PATH)
    reservations_from_config(config).map do |reservation|
      new(reservation_to_resource_hash(reservation))
    end
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || self::DEFAULT_CONFIG_PATH }.each do |path, grouped|
      config = config_for(path)
      reservations = reservations_from_config(config)

      grouped.each do |name, resource|
        match = find_reservation(reservations, name, resource[:scope_id], resource[:identifier_type], resource[:identifier])
        next unless match

        resource.provider = new(reservation_to_resource_hash(match[:reservation], match[:scope_id], path))
      end
    end
  end

  def self.reservations_from_config(config)
    dhcp4 = config.fetch(self::DHCP4_KEY, {})
    subnets = Array(dhcp4[self::SUBNET4_KEY])

    result = []
    subnets.each do |subnet|
      scope_id = subnet['id']
      next unless scope_id

      Array(subnet[RESERVATIONS_KEY]).each do |reservation|
        result << { scope_id: scope_id, reservation: reservation }
      end
    end
    result
  end

  def self.reservation_name(reservation, scope_id)
    identifier_type = reservation.key?('hw-address') ? 'hw-address' : 'client-id'
    identifier = reservation[identifier_type]
    hostname = reservation['hostname']

    reservation.dig('user-context', self::USER_CONTEXT_KEY) ||
      reservation['comment'] ||
      (hostname ? "#{hostname}-#{scope_id}" : "#{identifier_type}-#{identifier}-#{scope_id}")
  end

  def self.reservation_to_resource_hash(reservation_entry, scope_id = nil, path = self::DEFAULT_CONFIG_PATH)
    reservation = (reservation_entry.is_a?(Hash) && reservation_entry.key?(:reservation)) ? reservation_entry[:reservation] : reservation_entry
    scope_id ||= reservation_entry[:scope_id] if reservation_entry.is_a?(Hash)

    identifier_type = reservation.key?('hw-address') ? 'hw-address' : 'client-id'
    identifier = reservation[identifier_type]

    {
      ensure: :present,
      name: reservation_name(reservation, scope_id),
      scope_id: scope_id,
      identifier_type: identifier_type,
      identifier: identifier,
      ip_address: reservation['ip-address'],
      hostname: reservation['hostname'],
      config_path: path,
    }
  end

  def self.find_reservation(reservations, name, scope_id, identifier_type, identifier)
    reservations.each do |entry|
      reservation = entry[:reservation]
      next if scope_id && entry[:scope_id] != scope_id

      return entry if reservation_name(reservation, entry[:scope_id]) == name

      if identifier_type && identifier
        actual_type = reservation.key?('hw-address') ? 'hw-address' : 'client-id'
        return entry if actual_type == identifier_type && reservation[identifier_type] == identifier
      end
    end
    nil
  end

  def self.find_subnet_for_ip(subnets, ip_address)
    return nil unless ip_address

    target_ip = IPAddr.new(ip_address)

    subnets.each do |subnet|
      next unless subnet['subnet']

      subnet_cidr = IPAddr.new(subnet['subnet'])
      return subnet if subnet_cidr.include?(target_ip)
    end

    nil
  end

  def scope_id
    @property_hash[:scope_id]
  end

  def scope_id=(value)
    @property_flush[:scope_id] = value
  end

  def identifier_type
    @property_hash[:identifier_type]
  end

  def identifier_type=(value)
    @property_flush[:identifier_type] = value
  end

  def identifier
    @property_hash[:identifier]
  end

  def identifier=(value)
    @property_flush[:identifier] = value
  end

  def ip_address
    @property_hash[:ip_address]
  end

  def ip_address=(value)
    @property_flush[:ip_address] = value
  end

  def hostname
    @property_hash[:hostname]
  end

  def hostname=(value)
    @property_flush[:hostname] = value
  end

  def create
    @property_flush[:ensure] = :present
    @property_flush[:scope_id] = resource[:scope_id]
    @property_flush[:identifier_type] = resource[:identifier_type]
    @property_flush[:identifier] = resource[:identifier]
    @property_flush[:ip_address] = resource[:ip_address]
    @property_flush[:hostname] = resource[:hostname]
  end

  def destroy
    @property_flush[:ensure] = :absent
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def flush
    return if @property_flush.empty? && @property_hash.empty?

    config = self.class.config_for(config_path)
    config[self.class::DHCP4_KEY] ||= {}
    config[self.class::DHCP4_KEY][self.class::SUBNET4_KEY] ||= []
    subnets = config[self.class::DHCP4_KEY][self.class::SUBNET4_KEY]

    # Determine target subnet - either by explicit scope_id or by finding the subnet containing the IP
    target_scope_id = value_for(:scope_id)
    target_ip = value_for(:ip_address)

    subnet = if target_scope_id && target_scope_id != :auto
               subnets.find { |s| s['id'] == target_scope_id }
             else
               self.class.find_subnet_for_ip(subnets, target_ip)
             end

    if !subnet && target_scope_id && target_scope_id != :auto
      raise Puppet::Error, "Cannot find subnet with id #{target_scope_id}"
    end

    unless subnet
      raise Puppet::Error, "Cannot find subnet containing IP address #{target_ip}. Ensure a kea_dhcp_v4_scope exists that includes this IP."
    end

    subnet[RESERVATIONS_KEY] ||= []
    reservations = subnet[RESERVATIONS_KEY]

    current_identifier_type = (@property_flush[:identifier_type] || @property_hash[:identifier_type]).to_s
    current_identifier = @property_flush[:identifier] || @property_hash[:identifier]

    # Only treat as existing if we're updating a managed resource
    existing_reservation = if @property_hash[:ensure] == :present
                             find_reservation_in_array(reservations, current_identifier_type, current_identifier)
                           end

    if @property_flush[:ensure] == :absent
      if existing_reservation
        reservations.delete(existing_reservation)
        self.class.mark_dirty(config_path)
      end
      @property_hash.clear
      @property_flush.clear
      return
    end

    validate_uniqueness(reservations, existing_reservation, subnet)

    entry = existing_reservation || {}
    entry['user-context'] ||= {}
    entry['user-context'][self.class::USER_CONTEXT_KEY] = resource[:name]

    identifier_type = value_for(:identifier_type).to_s
    identifier = value_for(:identifier)
    ip_address = value_for(:ip_address)
    hostname = value_for(:hostname)

    # Clear old identifier type if it changed
    if existing_reservation
      old_type = existing_reservation.key?('hw-address') ? 'hw-address' : 'client-id'
      entry.delete(old_type) if old_type != identifier_type
    end

    entry[identifier_type] = identifier
    entry['ip-address'] = ip_address
    if hostname && !hostname.empty?
      entry['hostname'] = hostname
    else
      entry.delete('hostname')
    end

    reservations << entry unless existing_reservation

    self.class.mark_dirty(config_path)

    @property_hash = self.class.reservation_to_resource_hash(
      { scope_id: subnet['id'], reservation: entry },
      nil,
      config_path,
    )
    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)
    value = resource[key]
    value = @property_hash[key] if value.nil?
    value
  end

  def find_reservation_in_array(reservations, identifier_type, identifier)
    return nil unless identifier_type && identifier

    reservations.find do |r|
      r[identifier_type] == identifier
    end
  end

  def validate_uniqueness(reservations, existing_reservation, subnet)
    identifier_type = value_for(:identifier_type).to_s
    identifier = value_for(:identifier)
    ip_address = value_for(:ip_address)
    hostname = value_for(:hostname)
    subnet_id = subnet['id']
    subnet_cidr = subnet['subnet']

    reservations.each do |r|
      next if r.equal?(existing_reservation)

      # Check identifier uniqueness
      if r[identifier_type] == identifier
        raise Puppet::Error, "Reservation with #{identifier_type} '#{identifier}' already exists in subnet #{subnet_id} (#{subnet_cidr})"
      end

      # Check IP address uniqueness
      if r['ip-address'] == ip_address
        raise Puppet::Error, "Reservation with ip-address '#{ip_address}' already exists in subnet #{subnet_id} (#{subnet_cidr})"
      end

      # Check hostname uniqueness
      if hostname && !hostname.empty? && r['hostname'] == hostname
        raise Puppet::Error, "Reservation with hostname '#{hostname}' already exists in subnet #{subnet_id} (#{subnet_cidr})"
      end
    end
  end

  def self.post_resource_eval
    commit_uncontrolled!
  end
end
