# @summary Utility type for declaring multiple reservations
#
# @param name
#   Unique identifier for the reservation used only by Puppet
#
# @param identifier
#   The MAC address for the client (6-octet or 7-octet format)
#
# @param identifier_type
#   Type of identifier: 'hw-address' for hardware address or 'client-id' for client identifier
#
# @param ip_address
#   The reserved IPv4 address to assign to this client
#
# @param hostname
#   Optional hostname for the reservation. Defaults to the name if not specified
#
# @param scope_id
#   Optional numeric identifier for the subnet where this reservation belongs.
#   Set to 'auto' to auto-detect from ip_address. Defaults to auto-detection if not specified
type Kea_Dhcp::V4Reservation = Struct[
  name                  => String,
  identifier            => Kea_Dhcp::MacAddress,
  identifier_type       => Enum['hw-address', 'client-id'],
  ip_address            => Stdlib::IP::Address::V4,
  Optional[hostname]    => String,
  Optional[scope_id]    => Variant[Integer[0], Enum['auto']],
]
