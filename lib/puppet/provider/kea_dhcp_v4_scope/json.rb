# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'
require 'set'
require 'puppet/util/execution'

Puppet::Type.type(:kea_dhcp_v4_scope).provide(:json) do
  desc 'Manages Kea DHCPv4 scopes stored in the kea-dhcp4 JSON configuration.'

  DEFAULT_CONFIG_PATH = '/etc/kea/kea-dhcp4.conf'
  USER_CONTEXT_KEY = 'puppet_name'
  DHCP4_KEY = 'Dhcp4'
  SUBNET4_KEY = 'subnet4'

  confine feature: :json

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    config = config_for(DEFAULT_CONFIG_PATH)
    scopes_from_config(config).map do |scope|
      new(scope_to_resource_hash(scope))
    end
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || DEFAULT_CONFIG_PATH }.each do |path, grouped|
      config = config_for(path)
      scopes = scopes_from_config(config)

      grouped.each do |name, resource|
        match = find_scope(scopes, name, resource[:id])
        next unless match

        resource.provider = new(scope_to_resource_hash(match, path))
      end
    end
  end

  def self.load_config(path)
    contents = begin
                 File.read(path)
               rescue Errno::ENOENT
                 return default_config
               end

    JSON.parse(contents)
  rescue JSON::ParserError => e
    raise Puppet::Error, "Failed to parse #{path}: #{e.message}"
  end

  def self.default_config
    {
      DHCP4_KEY => {
        SUBNET4_KEY => [],
      },
    }
  end

  def self.scopes_from_config(config)
    dhcp4 = config.fetch(DHCP4_KEY, {})
    Array(dhcp4[SUBNET4_KEY])
  end

  def self.scope_name(scope)
    scope.dig('user-context', USER_CONTEXT_KEY) || scope['comment'] || "subnet-#{scope['id'] || scope['subnet']}"
  end

  def self.scope_to_resource_hash(scope, path = DEFAULT_CONFIG_PATH)
    {
      ensure: :present,
      name: scope_name(scope),
      id: scope['id'],
      subnet: scope['subnet'],
      pools: Array(scope['pools']).map { |pool| pool['pool'] },
      options: Array(scope['option-data']).map do |option|
        option.transform_keys(&:to_s)
      end,
      config_path: path,
    }
  end

  def self.find_scope(scopes, name, id)
    id = Integer(id) if id && id != :auto

    scopes.each do |scope|
      return scope if id && scope['id'] == id
      return scope if scope_name(scope) == name
    end
    nil
  end

  def self.config_cache
    @config_cache ||= {}
  end

  def self.dirty_paths
    @dirty_paths ||= Set.new
  end

  def self.config_for(path)
    config_cache[path] ||= load_config(path)
  end

  def self.mark_dirty(path)
    dirty_paths.add(path)
  end

  def self.clear_state!
    @config_cache = {}
    @dirty_paths = Set.new
  end

  def self.save_if_dirty(path)
    return unless dirty_paths.include?(path)

    config = config_for(path)

    temp_dir = Dir.mktmpdir('kea-dhcp4')
    begin
      temp_path = File.join(temp_dir, File.basename(path))
      File.write(temp_path, JSON.pretty_generate(config) + "\n")

      Puppet::Util::Execution.execute(['kea-dhcp4', '-t', '-c', temp_path], failonfail: true)

      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(temp_path, path)
    ensure
      FileUtils.remove_entry(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    dirty_paths.delete(path)
  end

  def config_path
    resource[:config_path] || DEFAULT_CONFIG_PATH
  end

  def id
    @property_hash[:id]
  end

  def id=(value)
    @property_flush[:id] = value
  end

  def subnet
    @property_hash[:subnet]
  end

  def subnet=(value)
    @property_flush[:subnet] = value
  end

  def pools
    @property_hash[:pools]
  end

  def pools=(value)
    @property_flush[:pools] = value
  end

  def options
    @property_hash[:options]
  end

  def options=(value)
    @property_flush[:options] = value
  end

  def create
    @property_flush[:ensure] = :present
    @property_flush[:id] = resource[:id]
    @property_flush[:subnet] = resource[:subnet]
    @property_flush[:pools] = resource[:pools] || []
    @property_flush[:options] = resource[:options] || []
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
    config[DHCP4_KEY] ||= {}
    config[DHCP4_KEY][SUBNET4_KEY] ||= []
    subnets = config[DHCP4_KEY][SUBNET4_KEY]

    current_id = @property_flush[:id]
    current_id = @property_hash[:id] if current_id.nil? || current_id == :auto

    scope = self.class.find_scope(subnets, resource[:name], current_id)

    if @property_flush[:ensure] == :absent
      if scope
        subnets.delete(scope)
        self.class.mark_dirty(config_path)
      end
      @property_hash.clear
      @property_flush.clear
      self.class.save_if_dirty(config_path)
      return
    end

    entry = scope || {}
    entry['user-context'] ||= {}
    entry['user-context'][USER_CONTEXT_KEY] = resource[:name]
    entry['subnet'] = value_for(:subnet)
    entry['id'] = resolved_id(subnets, entry, scope)
    entry['pools'] = Array(value_for(:pools)).map { |pool| { 'pool' => pool } }
    entry['option-data'] = Array(value_for(:options)).map do |option|
      option.transform_keys(&:to_s)
    end

    if scope
      subnets[subnets.index(scope)] = entry
    else
      subnets << entry
    end

    config[DHCP4_KEY] ||= {}
    config[DHCP4_KEY][SUBNET4_KEY] = subnets

    self.class.mark_dirty(config_path)
    self.class.save_if_dirty(config_path)

    @property_hash = self.class.scope_to_resource_hash(entry, config_path)
    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)
    value = resource[key]
    value = @property_hash[key] if value.nil?

    if [:pools, :options].include?(key) && value.nil?
      []
    else
      value
    end
  end

  def resolved_id(subnets, _entry, existing_scope)
    desired = value_for(:id)
    desired = nil if desired == :auto

    return existing_scope['id'] if existing_scope && desired.nil?

    if desired
      taken = subnets.reject { |s| s.equal?(existing_scope) }.map { |s| s['id'] }
      if taken.include?(desired)
        raise Puppet::Error, "Scope id #{desired} already in use"
      end
      return desired
    end

    baseline = subnets.map { |s| s['id'] }.compact.max || 0
    baseline + 1
  end
end
