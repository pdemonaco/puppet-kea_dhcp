# frozen_string_literal: true

require 'puppet/property/boolean'

Puppet::Type.newtype(:kea_dhcp_v4_scope) do
  @doc = 'Manages DHCPv4 subnets within the Kea kea-dhcp4.json configuration file.'

  newparam(:name, namevar: true) do
    desc 'A unique identifier for the scope used only by Puppet.'
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp4 configuration file.'
    defaultto '/etc/kea/kea-dhcp4.conf'
  end

  ensurable

  newproperty(:id) do
    desc 'The numeric identifier for the scope. Defaults to the next free identifier.'
    defaultto(:auto)

    munge do |value|
      next :auto if value == :auto || value == 'auto' || value.nil?

      Integer(value)
    rescue ArgumentError
      raise ArgumentError, "Scope id must be an integer, got #{value.inspect}"
    end

    def insync?(is)
      return true if should == :auto

      super
    end
  end

  newproperty(:subnet) do
    desc 'CIDR representation of the subnet (mandatory).'

    validate do |value|
      raise ArgumentError, 'Subnet must be provided' if value.nil? || value.empty?
      raise ArgumentError, "Invalid ipv4 subnet '#{value}'" if !value.match?(%r{^(25[0-5]|2[0-4]\d|1\d\d|[1-9]\d?)\.(?:25[0-5].|2[0-4]\d.|1\d\d.|[1-9]?\d\.){2}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\/(3[0-2]|[12]?\d)$})
    end
  end

  newproperty(:pools, array_matching: :all) do
    desc 'Array of pool definitions. Each entry is passed directly to Kea.'
    defaultto([])

    # TODO: add validation of pool entries. Each entry should either be an IPv4 CIDR string or two IPv4 addresses separated by a hyphen surrounded by spaces.

    def insync?(is)
      Array(is).sort == Array(should).sort
    end
  end

  newproperty(:options, array_matching: :all) do
    desc 'Array of option hashes (name, data, etc).'
    defaultto([])

    validate do |value|
      unless value.is_a?(Hash) && (value.key?('name') || value.key?(:name)) && (value.key?('data') || value.key?(:data))
        raise ArgumentError, 'Each option must be a hash containing at least name and data'
      end
    end
  end

  autorequire(:file) do
    [self[:config_path]]
  end

  validate do
    return if self[:ensure] == :absent

    raise ArgumentError, 'Subnet is a required property' if self[:subnet].nil?
  end
end
