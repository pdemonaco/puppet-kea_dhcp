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
    IPV4_SUBNET = %r{
      ^
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]\d?)\.
      (?:25[0-5]\.|2[0-4]\d\.|1\d\d\.|[1-9]?\d\.){2}
      (25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)
      /
      (3[0-2]|[12]?\d)
      $
    }x.freeze  # <- 'x' flag allows whitespace and comments
    validate do |value|
      raise ArgumentError, 'Subnet must be provided' if value.nil? || value.empty?
      raise ArgumentError, "Invalid ipv4 subnet '#{value}'" unless value.match?(IPV4_SUBNET)
    end
  end

  newproperty(:pools, array_matching: :all) do
    desc 'Array of pool definitions. Each entry is passed directly to Kea.'
    defaultto([])

    OCTET      = '(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
    IPV4       = "(?:#{OCTET}\\.){3}#{OCTET}"
    CIDR_REGEX = %r{\A#{IPV4}/(3[0-2]|[12]?\d)\z}.freeze
    RANGE_REGEX = %r{\A#{IPV4} - #{IPV4}\z}.freeze

    validate do |value|
      unless value.is_a?(String) && (CIDR_REGEX.match?(value) || RANGE_REGEX.match?(value))
        raise ArgumentError, 'Pool entries must be a CIDR or IPv4 range in the form "start - end"'
      end
    end

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

    def insync?(is)
      normalize(Array(is)) == normalize(Array(should))
    end

    def munge(value)
      result = stringify_keys(value)
      if result['data'].is_a?(Array)
        result['data'] = result['data'].join(', ')
      elsif result['data'].is_a?(String)
        result['data'] = result['data'].gsub(',', '\\,')
      end
      result
    end

    def normalize(collection)
      collection.map { |item| stringify_keys(item) }.map { |item| item.sort.to_h }.sort_by { |item| item.to_a }
    end
    private :normalize

    def stringify_keys(hash)
      return {} unless hash.respond_to?(:each)

      hash.each_with_object({}) do |(key, val), acc|
        acc[key.to_s] = val
      end
    end
    private :stringify_keys
  end

  newproperty(:valid_lifetime) do
    desc 'The valid lifetime of leases for this scope in seconds. Optional; absent if not set.'

    munge do |value|
      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "valid_lifetime must be an integer, got #{value.inspect}"
    end
  end

  newproperty(:renew_timer) do
    desc 'The T1 timer (renew timer) in seconds for this scope. Optional; absent if not set.'

    munge do |value|
      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "renew_timer must be an integer, got #{value.inspect}"
    end
  end

  newproperty(:rebind_timer) do
    desc 'The T2 timer (rebind timer) in seconds for this scope. Optional; absent if not set.'

    munge do |value|
      Integer(value)
    rescue ArgumentError, TypeError
      raise ArgumentError, "rebind_timer must be an integer, got #{value.inspect}"
    end
  end

  newproperty(:ddns_qualifying_suffix) do
    desc 'The qualifying suffix appended to partial domain names when generating FQDN for DDNS updates.'

    validate do |value|
      unless value.is_a?(String) && value.match?(%r{\A[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.?\z})
        raise ArgumentError, "ddns_qualifying_suffix must be a valid FQDN, got #{value.inspect}"
      end
    end
  end

  newproperty(:ddns_update_on_renew) do
    desc 'When true, instructs the server to update DNS on lease renewal even when the FQDN has not changed.'
    newvalues(:true, :false)

    def insync?(is)
      is.to_s == should.to_s
    end

    munge do |value|
      case value
      when true, 'true', :true then :true
      when false, 'false', :false then :false
      else raise ArgumentError, "ddns_update_on_renew must be a boolean, got #{value.inspect}"
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

  def generate
    path = self[:config_path]
    return [] if catalog.resource(:kea_dhcp_v4_commit, path)

    [Puppet::Type.type(:kea_dhcp_v4_commit).new(name: path)]
  end
end
