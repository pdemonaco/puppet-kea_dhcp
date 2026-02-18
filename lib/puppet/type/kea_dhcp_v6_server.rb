# frozen_string_literal: true

Puppet::Type.newtype(:kea_dhcp_v6_server) do
  @doc = 'Manages Kea DHCPv6 server level configuration.'

  newparam(:name, namevar: true) do
    desc 'The unique identifier for the DHCPv6 server configuration. Must be dhcp6.'

    validate do |value|
      raise ArgumentError, "Only the 'dhcp6' DHCPv6 server resource is supported" unless value == 'dhcp6'
    end
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp6 configuration file.'
    defaultto '/etc/kea/kea-dhcp6.conf'
  end

  ensurable

  newproperty(:options, array_matching: :all) do
    desc 'Array of DHCP option hashes applied at the server level (name, data, etc).'
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
      stringify_keys(value)
    end

    def normalize(collection)
      collection.map { |item| stringify_keys(item) }.map { |item| item.sort.to_h }.sort_by { |item| item.to_a }
    end
    private :normalize

    def stringify_keys(hash)
      return {} unless hash.respond_to?(:each)

      hash.each_with_object({}) do |(key, val), acc|
        acc[key.to_s] = unwrap_sensitive(val)
      end
    end
    private :stringify_keys

    def unwrap_sensitive(value)
      if value.respond_to?(:unwrap)
        value.unwrap
      else
        value
      end
    end
    private :unwrap_sensitive
  end

  newproperty(:hooks_libraries, array_matching: :all) do
    desc 'Array of hooks library configurations. Each element is a hash with at least a library key.'
    defaultto([])

    validate do |value|
      unless value.is_a?(Hash) && (value.key?('library') || value.key?(:library))
        raise ArgumentError, 'Each hooks library must be a hash containing at least a library key'
      end
    end

    def insync?(is)
      normalize(Array(is)) == normalize(Array(should))
    end

    def munge(value)
      stringify_keys(value)
    end

    def normalize(collection)
      collection.map { |item| stringify_keys(item) }.map { |item| item.sort.to_h }.sort_by { |item| item.to_a }
    end
    private :normalize

    def stringify_keys(hash)
      return {} unless hash.respond_to?(:each)

      hash.each_with_object({}) do |(key, val), acc|
        acc[key.to_s] = val.is_a?(Hash) ? stringify_keys(val) : val
      end
    end
    private :stringify_keys
  end

  newproperty(:lease_database) do
    desc 'Lease database configuration. Currently only the PostgreSQL backend is supported.'

    validate do |value|
      unless value.is_a?(Hash)
        raise ArgumentError, 'Lease database must be provided as a hash'
      end

      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }

      unless normalized['type'] == 'postgresql'
        raise ArgumentError, 'Only the postgresql lease database backend is supported'
      end

      ['name', 'user', 'password', 'host', 'port'].each do |key|
        raise ArgumentError, "Lease database #{key} must be provided" unless normalized.key?(key)
      end

      begin
        Integer(normalized['port'])
      rescue ArgumentError, TypeError
        raise ArgumentError, 'Lease database port must be an integer'
      end
    end

    def insync?(is)
      stringify_keys(is || {}) == stringify_keys(should || {})
    end

    def munge(value)
      normalized = stringify_keys(value)
      normalized['port'] = Integer(normalized['port'])
      normalized
    end

    def stringify_keys(hash)
      return {} unless hash.respond_to?(:each)

      hash.each_with_object({}) do |(key, val), acc|
        acc[key.to_s] = unwrap_sensitive(val)
      end
    end
    private :stringify_keys

    def unwrap_sensitive(value)
      if value.respond_to?(:unwrap)
        value.unwrap
      else
        value
      end
    end
    private :unwrap_sensitive
  end

  autorequire(:file) do
    [self[:config_path]]
  end
end
