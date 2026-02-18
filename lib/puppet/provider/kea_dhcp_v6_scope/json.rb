# frozen_string_literal: true

require 'puppet_x/kea_dhcp/provider/dhcp6_json'

Puppet::Type.type(:kea_dhcp_v6_scope).provide(:json, parent: PuppetX::KeaDhcp::Provider::Dhcp6Json) do
  desc 'Manages Kea DHCPv6 scopes stored in the kea-dhcp6 JSON configuration.'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    config = config_for(self::DEFAULT_CONFIG_PATH)
    scopes_from_config(config).map do |scope|
      new(scope_to_resource_hash(scope))
    end
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || self::DEFAULT_CONFIG_PATH }.each do |path, grouped|
      config = config_for(path)
      scopes = scopes_from_config(config)

      grouped.each do |name, resource|
        match = find_scope(scopes, name, resource[:id])
        next unless match

        resource.provider = new(scope_to_resource_hash(match, path))
      end
    end
  end

  def self.scopes_from_config(config)
    dhcp6 = config.fetch(self::DHCP6_KEY, {})
    Array(dhcp6[self::SUBNET6_KEY])
  end

  def self.scope_name(scope)
    scope.dig('user-context', self::USER_CONTEXT_KEY) || scope['comment'] || "subnet-#{scope['id'] || scope['subnet']}"
  end

  def self.scope_to_resource_hash(scope, path = self::DEFAULT_CONFIG_PATH)
    {
      ensure: :present,
      name: scope_name(scope),
      id: scope['id'],
      subnet: scope['subnet'],
      pools: Array(scope['pools']).map { |pool| pool['pool'] },
      pd_pools: Array(scope['pd-pools']).map { |pd| pd.transform_keys(&:to_s) },
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

  def pd_pools
    @property_hash[:pd_pools]
  end

  def pd_pools=(value)
    @property_flush[:pd_pools] = value
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
    @property_flush[:pd_pools] = resource[:pd_pools] || []
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
    config[self.class::DHCP6_KEY] ||= {}
    config[self.class::DHCP6_KEY][self.class::SUBNET6_KEY] ||= []
    subnets = config[self.class::DHCP6_KEY][self.class::SUBNET6_KEY]

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

    validate_unique_subnet!(subnets, scope)

    entry = scope || {}
    entry['user-context'] ||= {}
    entry['user-context'][self.class::USER_CONTEXT_KEY] = resource[:name]
    entry['subnet'] = value_for(:subnet)
    entry['id'] = resolved_id(subnets, entry, scope)
    entry['pools'] = Array(value_for(:pools)).map { |pool| { 'pool' => pool } }
    entry['pd-pools'] = Array(value_for(:pd_pools)).map { |pd| pd.transform_keys(&:to_s) }
    entry['option-data'] = Array(value_for(:options)).map do |option|
      option.transform_keys(&:to_s)
    end

    if scope
      subnets[subnets.index(scope)] = entry
    else
      subnets << entry
    end

    config[self.class::DHCP6_KEY] ||= {}
    config[self.class::DHCP6_KEY][self.class::SUBNET6_KEY] = subnets

    self.class.mark_dirty(config_path)
    self.class.save_if_dirty(config_path)

    @property_hash = self.class.scope_to_resource_hash(entry, config_path)
    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)
    value = resource[key]
    value = @property_hash[key] if value.nil?

    if [:pools, :pd_pools, :options].include?(key) && value.nil?
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

  def validate_unique_subnet!(subnets, existing_scope)
    desired_subnet = value_for(:subnet)
    subnets.each do |s|
      next if s.equal?(existing_scope)

      if s['subnet'] == desired_subnet
        raise Puppet::Error, "Subnet #{desired_subnet} is already defined in scope '#{self.class.scope_name(s)}'"
      end
    end
  end

  def self.post_resource_eval
    commit_uncontrolled!
  end
end
