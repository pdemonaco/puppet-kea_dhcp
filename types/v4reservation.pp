# @summary Utility type for declaring multiple reservations
type Kea_Dhcp::V4Reservation = Struct[
  name                  => String,
  identifier            => Kea_Dhcp::MacAddress,
  identifier_type       => Enum['hw-address', 'client-id'],
  ip_address            => Stdlib::IP::Address::V4,
  Optional[hostname]    => String,
  Optional[scope_id]    => Variant[Integer[0], Enum['auto']],
]
