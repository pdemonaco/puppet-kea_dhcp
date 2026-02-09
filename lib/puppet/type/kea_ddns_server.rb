# frozen_string_literal: true

Puppet::Type.newtype(:kea_ddns_server) do
  @doc = 'Manages Kea DHCP-DDNS server level configuration.'

  DDNS_SERVER_INSTANCE_NAME = 'dhcp-ddns'

  newparam(:name, namevar: true) do
    desc 'The unique identifier for the DHCP-DDNS server configuration. Must be dhcp-ddns.'

    validate do |value|
      raise ArgumentError, "Only the '#{DDNS_SERVER_INSTANCE_NAME}' DHCP-DDNS server resource is supported" unless value == DDNS_SERVER_INSTANCE_NAME
    end
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp-ddns configuration file.'
    defaultto '/etc/kea/kea-dhcp-ddns.conf'
  end

  ensurable

  newproperty(:ip_address) do
    desc 'IP address on which D2 listens for requests.'
    defaultto '127.0.0.1'

    validate do |value|
      unless value =~ %r{^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$} || value =~ %r{^[0-9a-fA-F:]+$}
        raise ArgumentError, 'ip_address must be a valid IPv4 or IPv6 address'
      end
    end
  end

  newproperty(:port) do
    desc 'Port on which D2 listens for requests.'
    defaultto 53_001

    validate do |value|
      begin
        port = Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, 'port must be an integer'
      end
      raise ArgumentError, 'port must be between 1 and 65535' unless port.between?(1, 65_535)
    end

    munge do |value|
      Integer(value)
    end
  end

  newproperty(:dns_server_timeout) do
    desc 'Maximum amount of time to wait for a response from a DNS server, in milliseconds.'
    defaultto 500

    validate do |value|
      begin
        timeout = Integer(value)
      rescue ArgumentError, TypeError
        raise ArgumentError, 'dns_server_timeout must be an integer'
      end
      raise ArgumentError, 'dns_server_timeout must be positive' unless timeout.positive?
    end

    munge do |value|
      Integer(value)
    end
  end

  newproperty(:ncr_protocol) do
    desc 'Socket protocol to use when sending requests to D2.'
    defaultto 'UDP'

    validate do |value|
      valid_protocols = ['UDP', 'TCP']
      raise ArgumentError, "ncr_protocol must be one of: #{valid_protocols.join(', ')}" unless valid_protocols.include?(value)
    end
  end

  newproperty(:ncr_format) do
    desc 'Packet format to use when sending requests to D2.'
    defaultto 'JSON'

    validate do |value|
      valid_formats = ['JSON']
      raise ArgumentError, "ncr_format must be one of: #{valid_formats.join(', ')}" unless valid_formats.include?(value)
    end
  end

  newproperty(:tsig_keys, array_matching: :all) do
    desc 'Array of TSIG key configurations for authenticating DNS updates.'
    defaultto([])

    validate do |value|
      unless value.is_a?(Hash)
        raise ArgumentError, 'Each TSIG key must be a hash'
      end

      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }

      ['name', 'algorithm', 'secret'].each do |key|
        raise ArgumentError, "TSIG key must contain #{key}" unless normalized.key?(key)
      end

      valid_algorithms = ['HMAC-MD5', 'HMAC-SHA1', 'HMAC-SHA224', 'HMAC-SHA256', 'HMAC-SHA384', 'HMAC-SHA512']
      unless valid_algorithms.include?(normalized['algorithm'])
        raise ArgumentError, "TSIG key algorithm must be one of: #{valid_algorithms.join(', ')}"
      end
    end

    def insync?(is)
      normalize(Array(is)) == normalize(Array(should))
    end

    def munge(value)
      stringify_keys(value)
    end

    def normalize(collection)
      collection.map { |item| stringify_keys(item) }.map { |item| item.sort.to_h }.sort_by { |item| item['name'] }
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

  autorequire(:file) do
    [self[:config_path]]
  end

  autobefore(:service) do
    ['kea-dhcp-ddns']
  end
end
