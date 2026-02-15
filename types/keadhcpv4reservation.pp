# @summary Utility type for declaring multiple reservations
type Kea_Dhcp::V4Reservation = Struct[
  name               => String,
  identifier         => Stdlib::MAC,
  identifier_type    => Enum['hw-address', 'client-id'],
  ip_address         => Stdlib::IP::Address::V4,
  Optional[hostname] => String,
]
