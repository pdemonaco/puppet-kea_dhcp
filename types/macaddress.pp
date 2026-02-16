# @summary MAC address format for Kea DHCP identifiers
#
# Supports 6-octet (XX:XX:XX:XX:XX:XX) or 7-octet (XX:XX:XX:XX:XX:XX:XX) formats
# with either colon or hyphen separators (but not mixed).
type Kea_Dhcp::MacAddress = Pattern[
  /\A([0-9a-fA-F]{2}[:-])([0-9a-fA-F]{2}[:-])([0-9a-fA-F]{2}[:-])([0-9a-fA-F]{2}[:-])([0-9a-fA-F]{2}[:-])([0-9a-fA-F]{2})([:-][0-9a-fA-F]{2})?\z/
]
