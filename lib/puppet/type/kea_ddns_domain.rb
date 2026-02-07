# frozen_string_literal: true

Puppet::Type.newtype(:kea_ddns_domain) do
  @doc = 'Manages Kea DHCP-DDNS domain configurations (forward or reverse).'

  newparam(:name, namevar: true) do
    desc 'The Puppet identifier for this DDNS domain.'
  end

  newparam(:config_path) do
    desc 'Path to the kea-dhcp-ddns configuration file.'
    defaultto '/etc/kea/kea-dhcp-ddns.conf'
  end

  ensurable

  newproperty(:domain_name) do
    desc 'The DNS domain name (e.g., "example.com." or "1.168.192.in-addr.arpa.").'

    validate do |value|
      raise ArgumentError, 'domain_name must be a string' unless value.is_a?(String)
      raise ArgumentError, 'domain_name cannot be empty' if value.strip.empty?
    end
  end

  newproperty(:direction) do
    desc 'The direction of this domain: "forward" or "reverse".'

    validate do |value|
      valid_directions = ['forward', 'reverse']
      raise ArgumentError, "direction must be one of: #{valid_directions.join(', ')}" unless valid_directions.include?(value)
    end
  end

  newproperty(:key_name) do
    desc 'Optional TSIG key name to use for all DNS servers in this domain (unless overridden per-server).'

    validate do |value|
      raise ArgumentError, 'key_name must be a string' unless value.is_a?(String)
    end
  end

  newproperty(:dns_servers, array_matching: :all) do
    desc 'Array of DNS server configurations (ip-address, port, optional key-name).'
    defaultto([])

    validate do |value|
      unless value.is_a?(Hash)
        raise ArgumentError, 'Each DNS server must be a hash'
      end

      normalized = value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v }

      raise ArgumentError, 'DNS server must contain ip-address' unless normalized.key?('ip-address')

      unless normalized['ip-address'] =~ %r{^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$} || normalized['ip-address'] =~ %r{^[0-9a-fA-F:]+$}
        raise ArgumentError, 'DNS server ip-address must be a valid IPv4 or IPv6 address'
      end

      if normalized.key?('port')
        begin
          port = Integer(normalized['port'])
        rescue ArgumentError, TypeError
          raise ArgumentError, 'DNS server port must be an integer'
        end
        raise ArgumentError, 'DNS server port must be between 1 and 65535' unless port.between?(1, 65_535)
      end
    end

    def insync?(is)
      normalize(Array(is)) == normalize(Array(should))
    end

    def munge(value)
      normalized = stringify_keys(value)
      normalized['port'] = Integer(normalized['port']) if normalized.key?('port')
      normalized
    end

    def normalize(collection)
      sorted = collection.map do |item|
        normalized = stringify_keys(item)
        normalized['port'] = Integer(normalized['port']) if normalized.key?('port')
        normalized.sort.to_h
      end
      sorted.sort_by { |item| item['ip-address'] }
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

  autorequire(:file) do
    [self[:config_path]]
  end

  autorequire(:kea_ddns_server) do
    catalog.resources.select { |res| res.is_a?(Puppet::Type.type(:kea_ddns_server)) }.map(&:title)
  end
end
