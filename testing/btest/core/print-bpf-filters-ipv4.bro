# @TEST-REQUIRES: bro -e 'print bro_has_ipv6()' | grep -q F
#
# @TEST-EXEC: bro -e '' >output
# @TEST-EXEC: cat packet_filter.log >>output
# @TEST-EXEC: bro PacketFilter::all_packets=F protocols/ssh >>output
# @TEST-EXEC: cat packet_filter.log >>output
# @TEST-EXEC: bro -f "port 42" -e '' >>output
# @TEST-EXEC: cat packet_filter.log >>output
# @TEST-EXEC: bro -C -f "port 56730" -r $TRACES/mixed-vlan-mpls.trace protocols/conn >>output
# @TEST-EXEC: cat packet_filter.log >>output
# @TEST-EXEC: btest-diff output
# @TEST-EXEC: btest-diff conn.log
