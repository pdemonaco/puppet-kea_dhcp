# frozen_string_literal: true

require 'puppet/property/boolean'

Puppet::Type.newtype(:kea_dhcp_v6_scope) do
  @doc = 'Manages DHCPv6 subnets within the Kea kea-dhcp6.json configuration file.'

  newparam(:name, namevar: true) do
    desc 'A unique identifier for the scope used only by Puppet.'
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp6 configuration file.'
    defaultto '/etc/kea/kea-dhcp6.conf'
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
    desc 'CIDR representation of the IPv6 subnet (mandatory).'
    IPV6_SUBNET = %r{
      ^
      [0-9a-fA-F:]+
      /
      (12[0-8]|1[01]\d|[1-9]?\d)
      $
    }x.freeze
    validate do |value|
      raise ArgumentError, 'Subnet must be provided' if value.nil? || value.empty?
      raise ArgumentError, "Invalid ipv6 subnet '#{value}'" unless value.match?(IPV6_SUBNET)
    end
  end

  newproperty(:pools, array_matching: :all) do
    desc 'Array of IPv6 pool definitions. Each entry is an IPv6 CIDR or range.'
    defaultto([])

    IPV6_CIDR_REGEX = %r{\A[0-9a-fA-F:]+/\d{1,3}\z}.freeze
    IPV6_RANGE_REGEX = %r{\A[0-9a-fA-F:]+ - [0-9a-fA-F:]+\z}.freeze

    validate do |value|
      unless value.is_a?(String) && (IPV6_CIDR_REGEX.match?(value) || IPV6_RANGE_REGEX.match?(value))
        raise ArgumentError, 'Pool entries must be an IPv6 CIDR or range in the form "start - end"'
      end
    end

    def insync?(is)
      Array(is).sort == Array(should).sort
    end
  end

  newproperty(:pd_pools, array_matching: :all) do
    desc 'Array of prefix delegation pool definitions.'
    defaultto([])

    validate do |value|
      unless value.is_a?(Hash)
        raise ArgumentError, 'Each pd-pool entry must be a hash'
      end

      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      raise ArgumentError, 'Each pd-pool must contain a prefix key' unless normalized.key?('prefix')
      raise ArgumentError, 'Each pd-pool must contain a prefix-len key' unless normalized.key?('prefix-len')
      raise ArgumentError, 'Each pd-pool must contain a delegated-len key' unless normalized.key?('delegated-len')

      begin
        Integer(normalized['prefix-len'])
      rescue ArgumentError, TypeError
        raise ArgumentError, 'prefix-len must be an integer'
      end

      begin
        Integer(normalized['delegated-len'])
      rescue ArgumentError, TypeError
        raise ArgumentError, 'delegated-len must be an integer'
      end
    end

    def insync?(is)
      normalize(Array(is)) == normalize(Array(should))
    end

    def munge(value)
      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }
      normalized['prefix-len'] = Integer(normalized['prefix-len'])
      normalized['delegated-len'] = Integer(normalized['delegated-len'])
      normalized
    end

    def normalize(collection)
      collection.map { |item| item.transform_keys(&:to_s) }.sort_by { |item| item.to_a }
    end
    private :normalize
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
