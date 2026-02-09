# frozen_string_literal: true

require 'puppet_x/kea_dhcp/provider/ddns_json'

Puppet::Type.type(:kea_ddns_server).provide(:json, parent: PuppetX::KeaDhcp::Provider::DdnsJson) do
  desc 'Manages the server level Kea DHCP-DDNS configuration stored in kea-dhcp-ddns.conf.'

  TSIG_KEYS_KEY = 'tsig-keys'
  SERVER_INSTANCE_NAME = 'dhcp-ddns'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    config = config_for(self::DEFAULT_CONFIG_PATH)
    server = ddns_config(config)
    return [] unless present?(server)

    [new(resource_hash(server, self::DEFAULT_CONFIG_PATH))]
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || self::DEFAULT_CONFIG_PATH }.each do |path, grouped|
      self.server_config_path = path
      config = config_for(path)
      server = ddns_config(config)
      next unless present?(server)

      grouped.each do |_name, resource|
        resource.provider = new(resource_hash(server, path))
      end
    end
  end

  def self.ddns_config(config)
    config.fetch(self::DDNS_KEY, {})
  end

  def self.present?(server_section)
    server_section.key?('ip-address') || server_section.key?('port') || server_section.key?(TSIG_KEYS_KEY)
  end

  def self.resource_hash(server_section, path)
    {
      ensure: :present,
      name: SERVER_INSTANCE_NAME,
      ip_address: server_section['ip-address'] || '127.0.0.1',
      port: server_section['port'] || 53_001,
      dns_server_timeout: server_section['dns-server-timeout'] || 500,
      ncr_protocol: server_section['ncr-protocol'] || 'UDP',
      ncr_format: server_section['ncr-format'] || 'JSON',
      tsig_keys: Array(server_section[TSIG_KEYS_KEY]).map { |key| stringify_keys(key) },
      config_path: path,
    }
  end

  def ip_address
    @property_hash[:ip_address]
  end

  def ip_address=(value)
    @property_flush[:ip_address] = value
  end

  def port
    @property_hash[:port]
  end

  def port=(value)
    @property_flush[:port] = value
  end

  def dns_server_timeout
    @property_hash[:dns_server_timeout]
  end

  def dns_server_timeout=(value)
    @property_flush[:dns_server_timeout] = value
  end

  def ncr_protocol
    @property_hash[:ncr_protocol]
  end

  def ncr_protocol=(value)
    @property_flush[:ncr_protocol] = value
  end

  def ncr_format
    @property_hash[:ncr_format]
  end

  def ncr_format=(value)
    @property_flush[:ncr_format] = value
  end

  def tsig_keys
    @property_hash[:tsig_keys]
  end

  def tsig_keys=(value)
    @property_flush[:tsig_keys] = value
  end

  def create
    @property_flush[:ensure] = :present
    @property_flush[:ip_address] = resource[:ip_address] || '127.0.0.1'
    @property_flush[:port] = resource[:port] || 53_001
    @property_flush[:dns_server_timeout] = resource[:dns_server_timeout] || 500
    @property_flush[:ncr_protocol] = resource[:ncr_protocol] || 'UDP'
    @property_flush[:ncr_format] = resource[:ncr_format] || 'JSON'
    @property_flush[:tsig_keys] = resource[:tsig_keys] || []
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
    config[self.class::DDNS_KEY] ||= { 'forward-ddns' => {}, 'reverse-ddns' => {} }
    ddns = config[self.class::DDNS_KEY]

    if @property_flush[:ensure] == :absent
      ddns.delete('ip-address')
      ddns.delete('port')
      ddns.delete('dns-server-timeout')
      ddns.delete('ncr-protocol')
      ddns.delete('ncr-format')
      ddns.delete(TSIG_KEYS_KEY)
      ensure_state = :absent
    else
      ddns['ip-address'] = value_for(:ip_address)
      ddns['port'] = value_for(:port)
      ddns['dns-server-timeout'] = value_for(:dns_server_timeout)
      ddns['ncr-protocol'] = value_for(:ncr_protocol)
      ddns['ncr-format'] = value_for(:ncr_format)
      tsig = Array(value_for(:tsig_keys)).map { |key| stringify_keys(key) }
      ddns[TSIG_KEYS_KEY] = tsig unless tsig.empty?
      ensure_state = :present
    end

    self.class.mark_dirty(config_path)

    @property_hash = if ensure_state == :present
                       self.class.resource_hash(ddns, config_path)
                     else
                       { ensure: :absent, name: resource[:name], config_path: config_path }
                     end

    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)

    value = resource[key]
    value = @property_hash[key] if value.nil?

    if key == :tsig_keys && value.nil?
      []
    else
      value
    end
  end

  def stringify_keys(hash)
    self.class.stringify_keys(hash)
  end

  def config_path
    path = resource[:config_path] || self.class::DEFAULT_CONFIG_PATH
    self.class.server_config_path = path
    self.class.register_commit_controller(path)
    path
  end

  def self.post_resource_eval
    commit_all!
    unregister_commit_controller(server_config_path) if server_config_path
  end
end
