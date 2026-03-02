# frozen_string_literal: true

require_relative '../../../puppet_x/kea_dhcp/provider/dhcp4_json'
require 'json'
require 'socket'

Puppet::Type.type(:kea_dhcp_v4_reservation).provide(:unix_socket, parent: PuppetX::KeaDhcp::Provider::Dhcp4Json) do
  desc 'Manages Kea DHCPv4 host reservations via the kea-dhcp4 control socket (libdhcp_host_cmds.so).'

  # Active only when a non-json host-database is configured in kea-dhcp4.conf.
  confine feature: :kea_host_database
  defaultfor feature: :kea_host_database

  DEFAULT_SOCKET_PATH = '/var/run/kea/kea4-ctrl-socket'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  # Only manage explicitly declared instances; do not auto-discover all reservations
  # from the host database to avoid unintended management of external records.
  def self.instances
    []
  end

  def self.prefetch(resources)
    resources.each do |name, resource|
      socket_path = resource[:socket_path] || DEFAULT_SOCKET_PATH
      next unless File.exist?(socket_path)

      identifier_type = resource[:identifier_type]&.to_s
      identifier = resource[:identifier]
      ip_address = resource[:ip_address]
      next unless identifier_type && identifier

      subnet_id = resolve_subnet_id(
        resource[:scope_id],
        ip_address,
        resource[:config_path] || self::DEFAULT_CONFIG_PATH,
      )
      next unless subnet_id

      response = send_command(socket_path, 'reservation-get', {
                                'subnet-id' => subnet_id,
                                'identifier-type' => identifier_type,
                                'identifier' => identifier,
                              })
      next unless response && response['result'] == 0

      reservation = response['arguments']
      next unless reservation

      resource.provider = new(
        ensure: :present,
        name: name,
        scope_id: subnet_id,
        identifier_type: identifier_type,
        identifier: identifier,
        ip_address: reservation['ip-address'],
        hostname: reservation['hostname'],
      )
    end
  end

  def self.resolve_subnet_id(scope_id, ip_address, config_path)
    return scope_id if scope_id && scope_id != :auto

    config = config_for(config_path)
    subnets = Array(config.dig(self::DHCP4_KEY, self::SUBNET4_KEY))
    subnet = find_subnet_for_ip(subnets, ip_address)
    subnet&.fetch('id', nil)
  end
  private_class_method :resolve_subnet_id

  def self.send_command(socket_path, command, arguments = {})
    UNIXSocket.open(socket_path) do |sock|
      request = JSON.generate({ 'command' => command, 'arguments' => arguments })
      sock.write(request)
      sock.close_write
      JSON.parse(sock.read)
    end
  rescue StandardError => e
    raise Puppet::Error, "Failed to communicate with kea-dhcp4 socket #{socket_path}: #{e.message}"
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

    socket_path = resource[:socket_path] || DEFAULT_SOCKET_PATH

    unless File.exist?(socket_path)
      raise Puppet::Error,
            "kea-dhcp4 control socket #{socket_path} not found. Ensure kea-dhcp4 is running."
    end

    Puppet.debug do
      "kea_dhcp_v4_reservation[#{resource[:name]}] (unix_socket): " \
        "scope_id=#{value_for(:scope_id).inspect} " \
        "identifier_type=#{value_for(:identifier_type).inspect} " \
        "identifier=#{value_for(:identifier).inspect} " \
        "ip_address=#{value_for(:ip_address).inspect} hostname=#{value_for(:hostname).inspect}"
    end

    subnet_id = resolve_subnet_id_for_flush

    if @property_flush[:ensure] == :absent
      flush_absent(socket_path, subnet_id)
      return
    end

    flush_present(socket_path, subnet_id)
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)

    value = resource[key]
    value = @property_hash[key] if value.nil?
    value
  end

  private

  def resolve_subnet_id_for_flush
    target_scope_id = value_for(:scope_id)
    target_ip = value_for(:ip_address)

    if target_scope_id && target_scope_id != :auto
      return target_scope_id
    end

    config = self.class.config_for(config_path)
    subnets = Array(config.dig(self.class::DHCP4_KEY, self.class::SUBNET4_KEY))
    subnet = self.class.find_subnet_for_ip(subnets, target_ip)

    unless subnet
      raise Puppet::Error,
            "Cannot find subnet containing IP address #{target_ip}. " \
            'Ensure a kea_dhcp_v4_scope exists that includes this IP.'
    end

    subnet['id']
  end

  def flush_absent(socket_path, subnet_id)
    id_type = (@property_hash[:identifier_type] || value_for(:identifier_type)).to_s
    id_val = @property_hash[:identifier] || value_for(:identifier)

    response = self.class.send_command(socket_path, 'reservation-del', {
                                         'subnet-id' => subnet_id,
                                         'identifier-type' => id_type,
                                         'identifier' => id_val,
                                       })

    # result 3 = not found, which is acceptable for absent
    if response['result'] != 0 && response['result'] != 3
      raise Puppet::Error, "reservation-del failed: #{response['text']}"
    end

    @property_hash.clear
    @property_flush.clear
  end

  def flush_present(socket_path, subnet_id)
    identifier_type = value_for(:identifier_type).to_s
    identifier = value_for(:identifier)
    ip_address = value_for(:ip_address)
    hostname = value_for(:hostname)

    validate_uniqueness(socket_path, subnet_id, identifier_type, identifier, ip_address)

    current = fetch_current_reservation(socket_path, subnet_id, identifier_type, identifier)

    reservation_data = build_reservation_data(subnet_id, identifier_type, identifier, ip_address, hostname)

    if current
      unless reservation_needs_update?(current, reservation_data, identifier_type)
        @property_flush.clear
        return
      end

      response = self.class.send_command(socket_path, 'reservation-update',
                                         { 'reservation' => reservation_data })
      raise Puppet::Error, "reservation-update failed: #{response['text']}" if response['result'] != 0
    else
      response = self.class.send_command(socket_path, 'reservation-add',
                                         { 'reservation' => reservation_data })
      raise Puppet::Error, "reservation-add failed: #{response['text']}" if response['result'] != 0
    end

    @property_hash = {
      ensure: :present,
      name: resource[:name],
      scope_id: subnet_id,
      identifier_type: identifier_type,
      identifier: identifier,
      ip_address: ip_address,
      hostname: hostname,
    }
    @property_flush.clear
  end

  def validate_uniqueness(socket_path, subnet_id, identifier_type, identifier, ip_address)
    # Check ip_address is not already reserved by a different identifier
    ip_response = self.class.send_command(socket_path, 'reservation-get', {
                                            'subnet-id' => subnet_id,
                                            'ip-address' => ip_address,
                                          })

    return unless ip_response['result'] == 0

    existing = ip_response['arguments']
    return unless existing

    existing_id_type = existing.key?('hw-address') ? 'hw-address' : 'client-id'
    existing_id = existing[existing_id_type]
    return if existing_id_type == identifier_type && existing_id == identifier

    raise Puppet::Error,
          "Reservation with ip-address '#{ip_address}' already exists for " \
          "#{existing_id_type} '#{existing_id}' in subnet #{subnet_id}"
  end

  def fetch_current_reservation(socket_path, subnet_id, identifier_type, identifier)
    response = self.class.send_command(socket_path, 'reservation-get', {
                                         'subnet-id' => subnet_id,
                                         'identifier-type' => identifier_type,
                                         'identifier' => identifier,
                                       })
    (response['result'] == 0) ? response['arguments'] : nil
  end

  def build_reservation_data(subnet_id, identifier_type, identifier, ip_address, hostname)
    data = { 'subnet-id' => subnet_id, identifier_type => identifier, 'ip-address' => ip_address }
    data['hostname'] = hostname if hostname && !hostname.empty?
    data
  end

  def reservation_needs_update?(current, desired, identifier_type)
    current[identifier_type] != desired[identifier_type] ||
      current['ip-address'] != desired['ip-address'] ||
      current.fetch('hostname', nil) != desired.fetch('hostname', nil)
  end
end
