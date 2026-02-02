# frozen_string_literal: true

Puppet::Type.newtype(:kea_dhcp_v4_reservation) do
  @doc = 'Manages DHCPv4 host reservations within a subnet in the Kea kea-dhcp4.json configuration file.'

  newparam(:name, namevar: true) do
    desc 'A unique identifier for the reservation used only by Puppet.'
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp4 configuration file.'
    defaultto '/etc/kea/kea-dhcp4.conf'
  end

  ensurable

  newproperty(:scope_id) do
    desc 'The numeric identifier for the subnet where this reservation belongs.'

    munge do |value|
      Integer(value)
    rescue ArgumentError
      raise ArgumentError, "Scope id must be an integer, got #{value.inspect}"
    end
  end

  newproperty(:identifier_type) do
    desc 'Type of identifier: hw-address or client-id.'
    newvalues('hw-address', 'client-id')
  end

  newproperty(:identifier) do
    desc 'The MAC address (hw-address) or client identifier value.'

    validate do |value|
      raise ArgumentError, 'Identifier must be provided' if value.nil? || value.empty?
    end
  end

  newproperty(:ip_address) do
    desc 'The reserved IPv4 address.'
    IPV4 = %r{
      ^
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)
      $
    }x.freeze

    validate do |value|
      raise ArgumentError, 'IP address must be provided' if value.nil? || value.empty?
      raise ArgumentError, "Invalid IPv4 address '#{value}'" unless value.match?(IPV4)
    end
  end

  newproperty(:hostname) do
    desc 'Optional hostname for the reservation.'
  end

  autorequire(:file) do
    [self[:config_path]]
  end

  autorequire(:kea_dhcp_v4_scope) do
    catalog.resources.select { |r| r.is_a?(Puppet::Type.type(:kea_dhcp_v4_scope)) }
  end

  validate do
    return if self[:ensure] == :absent

    raise ArgumentError, 'scope_id is required' if self[:scope_id].nil?
    raise ArgumentError, 'identifier_type is required' if self[:identifier_type].nil?
    raise ArgumentError, 'identifier is required' if self[:identifier].nil?
    raise ArgumentError, 'ip_address is required' if self[:ip_address].nil?
  end
end
