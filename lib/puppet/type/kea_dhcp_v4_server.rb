# frozen_string_literal: true

Puppet::Type.newtype(:kea_dhcp_v4_server) do
  @doc = 'Manages Kea DHCPv4 server level configuration.'

  INSTANCE_NAME = 'dhcp4'

  newparam(:name, namevar: true) do
    desc 'The unique identifier for the DHCPv4 server configuration. Must be dhcp4.'

    validate do |value|
      raise ArgumentError, "Only the '#{INSTANCE_NAME}' DHCPv4 server resource is supported" unless value == INSTANCE_NAME
    end
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp4 configuration file.'
    defaultto '/etc/kea/kea-dhcp4.conf'
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

  newproperty(:dhcp_ddns) do
    desc 'DHCP-DDNS connectivity and behavioral parameters.'

    validate do |value|
      unless value.is_a?(Hash)
        raise ArgumentError, 'dhcp_ddns must be provided as a hash'
      end

      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }

      if normalized.key?('enable-updates') && ![true, false].include?(normalized['enable-updates'])
        raise ArgumentError, 'enable-updates must be a boolean'
      end

      if normalized.key?('server-port')
        begin
          port = Integer(normalized['server-port'])
        rescue ArgumentError, TypeError
          raise ArgumentError, 'server-port must be an integer'
        end
        raise ArgumentError, 'server-port must be between 1 and 65535' unless port.between?(1, 65_535)
      end

      if normalized.key?('sender-port')
        begin
          port = Integer(normalized['sender-port'])
        rescue ArgumentError, TypeError
          raise ArgumentError, 'sender-port must be an integer'
        end
        raise ArgumentError, 'sender-port must be between 0 and 65535' unless port.between?(0, 65_535)
      end

      if normalized.key?('max-queue-size')
        begin
          size = Integer(normalized['max-queue-size'])
        rescue ArgumentError, TypeError
          raise ArgumentError, 'max-queue-size must be an integer'
        end
        raise ArgumentError, 'max-queue-size must be positive' unless size.positive?
      end

      valid_protocols = ['UDP', 'TCP']
      if normalized.key?('ncr-protocol') && !valid_protocols.include?(normalized['ncr-protocol'])
        raise ArgumentError, "ncr-protocol must be one of: #{valid_protocols.join(', ')}"
      end

      valid_formats = ['JSON']
      if normalized.key?('ncr-format') && !valid_formats.include?(normalized['ncr-format'])
        raise ArgumentError, "ncr-format must be one of: #{valid_formats.join(', ')}"
      end

      valid_replace_modes = ['never', 'always', 'when-present', 'when-not-present']
      if normalized.key?('ddns-replace-client-name') && !valid_replace_modes.include?(normalized['ddns-replace-client-name'])
        raise ArgumentError, "ddns-replace-client-name must be one of: #{valid_replace_modes.join(', ')}"
      end

      valid_resolution_modes = ['check-with-dhcid', 'no-check-with-dhcid', 'check-exists-with-dhcid', 'no-check-without-dhcid']
      if normalized.key?('ddns-conflict-resolution-mode') && !valid_resolution_modes.include?(normalized['ddns-conflict-resolution-mode'])
        raise ArgumentError, "ddns-conflict-resolution-mode must be one of: #{valid_resolution_modes.join(', ')}"
      end
    end

    def insync?(is)
      stringify_keys(is || {}) == stringify_keys(should || {})
    end

    def munge(value)
      normalized = stringify_keys(value)
      normalized['server-port'] = Integer(normalized['server-port']) if normalized.key?('server-port')
      normalized['sender-port'] = Integer(normalized['sender-port']) if normalized.key?('sender-port')
      normalized['max-queue-size'] = Integer(normalized['max-queue-size']) if normalized.key?('max-queue-size')
      normalized
    end

    def stringify_keys(hash)
      return {} unless hash.respond_to?(:each)

      hash.each_with_object({}) do |(key, val), acc|
        acc[key.to_s] = val
      end
    end
    private :stringify_keys
  end

  autorequire(:file) do
    [self[:config_path]]
  end
end
