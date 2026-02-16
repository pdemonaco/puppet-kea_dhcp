# frozen_string_literal: true

require 'puppet_x/kea_dhcp/provider/ddns_json'

Puppet::Type.type(:kea_ddns_domain).provide(:json, parent: PuppetX::KeaDhcp::Provider::DdnsJson) do
  desc 'Manages DDNS domain configurations in kea-dhcp-ddns.conf.'

  FORWARD_DDNS_KEY = 'forward-ddns'
  REVERSE_DDNS_KEY = 'reverse-ddns'
  DDNS_DOMAINS_KEY = 'ddns-domains'

  def initialize(value = {})
    super(value)
    @property_flush = {}
  end

  def self.instances
    instances = []
    config = config_for(self::DEFAULT_CONFIG_PATH)
    ddns = config.fetch(self::DDNS_KEY, {})

    # Get forward domains
    forward_ddns = ddns.fetch(FORWARD_DDNS_KEY, {})
    forward_domains = Array(forward_ddns[DDNS_DOMAINS_KEY])
    forward_domains.each do |domain|
      instances << new(domain_to_hash(domain, 'forward', self::DEFAULT_CONFIG_PATH))
    end

    # Get reverse domains
    reverse_ddns = ddns.fetch(REVERSE_DDNS_KEY, {})
    reverse_domains = Array(reverse_ddns[DDNS_DOMAINS_KEY])
    reverse_domains.each do |domain|
      instances << new(domain_to_hash(domain, 'reverse', self::DEFAULT_CONFIG_PATH))
    end

    instances
  end

  def self.prefetch(resources)
    resources.group_by { |_, res| res[:config_path] || self::DEFAULT_CONFIG_PATH }.each do |path, grouped|
      config = config_for(path)
      ddns = config.fetch(self::DDNS_KEY, {})

      grouped.each do |name, resource|
        direction = resource[:direction]
        next unless direction

        domain = find_domain(ddns, direction, name, resource[:domain_name])
        resource.provider = new(domain_to_hash(domain, direction, path)) if domain
      end
    end
  end

  def self.find_domain(ddns, direction, puppet_name, domain_name)
    section_key = if direction == 'forward'
                    FORWARD_DDNS_KEY
                  else
                    REVERSE_DDNS_KEY
                  end
    section = ddns.fetch(section_key, {})
    domains = Array(section[DDNS_DOMAINS_KEY])

    # First try to find by puppet_name in user-context
    found = domains.find do |d|
      uc = d.dig(self::USER_CONTEXT_KEY, self::PUPPET_NAME_KEY)
      uc == puppet_name
    end

    # Fall back to matching by domain name
    found ||= domains.find { |d| d['name'] == domain_name } if domain_name

    found
  end

  def self.domain_to_hash(domain, direction, path)
    puppet_name = domain.dig(self::USER_CONTEXT_KEY, self::PUPPET_NAME_KEY) || domain['name']
    {
      ensure: :present,
      name: puppet_name,
      domain_name: domain['name'],
      direction: direction,
      key_name: domain['key-name'],
      dns_servers: Array(domain['dns-servers']).map { |srv| stringify_keys(srv) },
      config_path: path,
    }
  end

  def direction
    @property_hash[:direction]
  end

  def direction=(value)
    @property_flush[:direction] = value
  end

  def key_name
    @property_hash[:key_name]
  end

  def key_name=(value)
    @property_flush[:key_name] = value
  end

  def dns_servers
    @property_hash[:dns_servers]
  end

  def dns_servers=(value)
    @property_flush[:dns_servers] = value
  end

  def create
    @property_flush[:ensure] = :present
    @property_flush[:direction] = resource[:direction]
    @property_flush[:key_name] = resource[:key_name]
    @property_flush[:dns_servers] = resource[:dns_servers] || []
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
    config[self.class::DDNS_KEY] ||= { FORWARD_DDNS_KEY => {}, REVERSE_DDNS_KEY => {} }
    ddns = config[self.class::DDNS_KEY]

    direction = value_for(:direction) || @property_hash[:direction]
    raise Puppet::Error, 'direction must be specified' unless direction

    section_key = if direction == 'forward'
                    FORWARD_DDNS_KEY
                  else
                    REVERSE_DDNS_KEY
                  end
    ddns[section_key] ||= {}
    ddns[section_key][DDNS_DOMAINS_KEY] ||= []
    domains = ddns[section_key][DDNS_DOMAINS_KEY]

    if @property_flush[:ensure] == :absent
      # Remove domain by puppet_name or domain_name
      domains.reject! do |d|
        d.dig(self.class::USER_CONTEXT_KEY, self.class::PUPPET_NAME_KEY) == resource[:name] ||
          d['name'] == @property_hash[:domain_name]
      end
      ensure_state = :absent
    else
      # Find existing domain or create new entry
      domain = domains.find do |d|
        d.dig(self.class::USER_CONTEXT_KEY, self.class::PUPPET_NAME_KEY) == resource[:name] ||
          d['name'] == @property_hash[:domain_name]
      end

      unless domain
        domain = {}
        domains << domain
      end

      # Set user-context for Puppet management
      domain[self.class::USER_CONTEXT_KEY] ||= {}
      domain[self.class::USER_CONTEXT_KEY][self.class::PUPPET_NAME_KEY] = resource[:name]

      # Set properties
      domain['name'] = value_for(:domain_name)
      key_name_val = value_for(:key_name)
      if key_name_val && !key_name_val.empty?
        domain['key-name'] = key_name_val
      else
        domain.delete('key-name')
      end

      dns_servers_val = Array(value_for(:dns_servers)).map { |srv| stringify_keys(srv) }
      domain['dns-servers'] = dns_servers_val unless dns_servers_val.empty?

      ensure_state = :present
    end

    self.class.mark_dirty(config_path)

    @property_hash = if ensure_state == :present
                       self.class.domain_to_hash(
                         domains.find { |d| d.dig(self.class::USER_CONTEXT_KEY, self.class::PUPPET_NAME_KEY) == resource[:name] },
                         direction,
                         config_path,
                       )
                     else
                       { ensure: :absent, name: resource[:name], config_path: config_path }
                     end

    @property_flush.clear
  end

  def value_for(key)
    return @property_flush[key] if @property_flush.key?(key)

    value = resource[key]
    value = @property_hash[key] if value.nil?

    if key == :dns_servers && value.nil?
      []
    elsif key == :domain_name && value.nil?
      resource[:domain_name]
    else
      value
    end
  end

  def stringify_keys(hash)
    self.class.stringify_keys(hash)
  end

  def config_path
    resource[:config_path] || self.class::DEFAULT_CONFIG_PATH
  end

  def self.post_resource_eval
    commit_uncontrolled!
  end
end
