# frozen_string_literal: true

require 'puppet_x/kea_dhcp/provider/json'

Puppet::Type.type(:kea_dhcp_v4_server).provide(:json, parent: PuppetX::KeaDhcp::Provider::Json) do
  desc 'Manages the server level Kea DHCPv4 configuration stored in kea-dhcp4.json.'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    config = config_for(self::DEFAULT_CONFIG_PATH)
    server = dhcp4_config(config)
    return [] unless present?(server)

    [new(resource_hash(server, self::DEFAULT_CONFIG_PATH))]
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || self::DEFAULT_CONFIG_PATH }.each do |path, grouped|
      self.server_config_path = path
      config = config_for(path)
      server = dhcp4_config(config)
      next unless present?(server)

      grouped.each do |_name, resource|
        resource.provider = new(resource_hash(server, path))
      end
    end
  end

  def self.dhcp4_config(config)
    config.fetch(self::DHCP4_KEY, {})
  end

  def self.present?(server_section)
    server_section.key?(self::LEASE_DATABASE_KEY) || server_section.key?(self::OPTION_DATA_KEY) || server_section.key?(self::HOOKS_LIBRARIES_KEY)
  end

  def self.resource_hash(server_section, path)
    {
      ensure: :present,
      name: self::SERVER_INSTANCE_NAME,
      options: Array(server_section[self::OPTION_DATA_KEY]).map { |opt| stringify_keys(opt) },
      hooks_libraries: Array(server_section[self::HOOKS_LIBRARIES_KEY]).map { |hook| deep_stringify_keys(hook) },
      lease_database: stringify_keys(server_section[self::LEASE_DATABASE_KEY]),
      config_path: path,
    }
  end

  def self.deep_stringify_keys(hash)
    return hash unless hash.respond_to?(:each)

    hash.each_with_object({}) do |(key, val), acc|
      acc[key.to_s] = val.is_a?(Hash) ? deep_stringify_keys(val) : val
    end
  end

  def options
    @property_hash[:options]
  end

  def options=(value)
    @property_flush[:options] = value
  end

  def hooks_libraries
    @property_hash[:hooks_libraries]
  end

  def hooks_libraries=(value)
    @property_flush[:hooks_libraries] = value
  end

  def lease_database
    @property_hash[:lease_database]
  end

  def lease_database=(value)
    @property_flush[:lease_database] = value
  end

  def create
    @property_flush[:ensure] = :present
    @property_flush[:options] = resource[:options] || []
    @property_flush[:hooks_libraries] = resource[:hooks_libraries] || []
    @property_flush[:lease_database] = resource[:lease_database] || {}
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
    config[self.class::DHCP4_KEY] ||= {}
    dhcp4 = config[self.class::DHCP4_KEY]

    if @property_flush[:ensure] == :absent
      dhcp4.delete(self.class::OPTION_DATA_KEY)
      dhcp4.delete(self.class::HOOKS_LIBRARIES_KEY)
      dhcp4.delete(self.class::LEASE_DATABASE_KEY)
      ensure_state = :absent
    else
      dhcp4[self.class::OPTION_DATA_KEY] = Array(value_for(:options)).map { |opt| stringify_keys(opt) }
      hooks_libs = Array(value_for(:hooks_libraries)).map { |hook| deep_stringify_keys(hook) }
      dhcp4[self.class::HOOKS_LIBRARIES_KEY] = hooks_libs unless hooks_libs.empty?
      lease_db = stringify_keys(value_for(:lease_database))
      dhcp4[self.class::LEASE_DATABASE_KEY] = lease_db unless lease_db.empty?
      ensure_state = :present
    end

    self.class.mark_dirty(config_path)
    self.class.save_if_dirty(config_path)

    @property_hash = if ensure_state == :present
                       self.class.resource_hash(dhcp4, config_path)
                     else
                       { ensure: :absent, name: resource[:name], config_path: config_path }
                     end

    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)

    value = resource[key]
    value = @property_hash[key] if value.nil?

    if [:options, :hooks_libraries].include?(key) && value.nil?
      []
    else
      value
    end
  end

  def stringify_keys(hash)
    self.class.stringify_keys(hash)
  end

  def deep_stringify_keys(hash)
    self.class.deep_stringify_keys(hash)
  end

  def config_path
    path = super
    self.class.server_config_path = path
    self.class.register_commit_controller(path)
    path
  end

  def self.post_resource_eval
    commit_all!
    unregister_commit_controller(server_config_path) if server_config_path
  end
end
