# frozen_string_literal: true

require 'json'

# Feature indicating that a non-json kea host-database is configured in
# kea-dhcp4.conf. When true, the unix_socket reservation provider is active.
Puppet.features.add(:kea_host_database, libs: []) do
  config_path = '/etc/kea/kea-dhcp4.conf'
  begin
    config = JSON.parse(File.read(config_path))
    host_db = config.dig('Dhcp4', 'hosts-database')
    host_db.is_a?(Hash) && !host_db.empty? && host_db['type'] != 'json'
  rescue StandardError
    false
  end
end
