# Window Capacity (not ICTCP)
# Check Args
if {$argc != 5} {
  puts "Usage: ns incast <srv_num> <wndcap-pkt> <SRU-KB> <link_buf-pkt> <seed>"
  exit 1
}

#################################################################
# Argments
# ServerNum: $argv(0)
set svr_num [lindex $argv 0]
# Window Capacity that is Summention of Advertized Windows (pkt): $argv(1)
set wnd_cap [lindex $argv 1]
# SRU Size (Byte) ... only Payload: $argv(2)
set SRU [expr [lindex $argv 2] * 1024]
# Link Buffer (pkt): $argv(3)
set link_buf [lindex $argv 3]
# Random Seed: $argv(4)
set seed [lindex $argv 4]

################################################################
# Variables
# Create a simulator object
set ns [new Simulator]

# Bandwidth (Gbps)
set bw_Gbps 1

# Link Delay (us)
set link_del_us 25
# Maximum Random Link Delay: 0--(maxrand-1) (us)
set maxrand_link_del_us 20

# SYN Interval Delay (us) for each Request
set SYN_del_us 0
## For Aggressive Optimization for Goodput (may cause incast)
#set SYN_del_us [expr int(${SRU} * 8 / (${bw_Gbps} * pow(10, 9)) * pow(10, 6))]
## For Conservative Optimization for Goodput (never cause incast)
# set SYN_del_us [expr int(${SRU} * 8 / (${bw_Gbps} * pow(10, 9)) * pow(10, 6)\
#   + ${link_del_us} * 4 * (1 + \
#   (log10( ${link_del_us} * 4 * pow(10, -6) * ${bw_Gbps} * pow(10, 9) \
#   / (1500 * 8) ) / log10(2))))]

# Maximum Random SYN Delay: 0--maxrand (us)
set maxrand_SYN_del_us 0

# Total Size of All Servers SRU with TCP/IP Header and Handshake
set SRU_trans [expr (int($SRU / 1460) + 1) * 1500 + 40]
set Block_trans [expr ${SRU_trans} * ${svr_num}]

# Link Error Rate (Unit:pkt) 0.001 = 0.1% (a loss in 1000 pkt)
# set err_rate 0.001
set err_rate 0

##############################################
# Constant / Global Variable
set sub_slot_T [expr $link_del_us * 4]
set tick 0.0000001; # 100ns

#############################################
# Random Model
set rng [new RNG]
# seed 0 equal to current OS time (UTC)
# so seed should be more than 1 for repeatability
$rng seed [expr ${seed} * ${svr_num} + 1]

#################################################################
# Calculate Advertized Windows from Window Capacity
set adv_wnd [expr int(${wnd_cap}/${svr_num})]
if {$adv_wnd < 2} {
	set adv_wnd 2
}

# for limiting the number of flows
set next_flowid 0

#################################################################
# Tracing Message
puts -nonewline "Server: $svr_num, wnd: ${adv_wnd}pkt, "
puts -nonewline "SRU: [lindex $argv 2]KB, link_buf: ${link_buf}pkt, "
puts "Seed: $seed, "
puts -nonewline "Block_trans: ${Block_trans}B, "
puts -nonewline "RTT: [expr $link_del_us * 4]us, "
puts -nonewline "RTT_rand: ${maxrand_link_del_us}us, "
puts "SYN_del: ${SYN_del_us}-[expr $SYN_del_us + $maxrand_SYN_del_us]us"

Agent/TCP set trace_all_oneline_ true
Agent/TCP set packetSize_ 1460
Agent/TCP set window_ $adv_wnd
Agent/TCP set singledup_ 0 ;      # 0: Disabled Limited Transmit
Agent/TCP set tcpTick_ 0.0000001 ;  # 100ns (default 0.01: 10ms)

##############################################
#Open the ns trace file and trace counter
set nf [open out.ns w]
$ns trace-all $nf
set ef [open out.et w]
$ns eventtrace-all $ef
set tf [open out.tcp w]
set whf [open window_history a]

# Maximum value of summention of Advertised windows
set max_wndcap 0
# Current value of summention of Advertised windows
set cur_sum_wnd 0
# Zero Transmitted Data (0 bytes) Counter
# that means flow is finished or incast occurred
set zero_data_cnt 0
# Previous Total bytes for all flows
set total_bytes_prev 0

proc finish {} {
	global ns nf ef tf whf
    $ns flush-trace
    close $nf
    close $tf
    close $ef
	close $whf
    puts "Done."
    exit 0
}
##############################################
# Trace Message
# Store the maximum summention of Advertized windows
puts $whf "0\t${wnd_cap}\t${svr_num}\t${SRU}\t${seed}"

#############################################
# Send SYN Packet
proc send_syn {flowid time} {
	global ns link_del_us ftp_ SRU
	$ns at [expr $time + ${link_del_us} * 2 * 0.000001] \
		"$ftp_($flowid) send $SRU"
}


##############################################
#Create a Switch and a Client node
set nx [$ns node]
set nc [$ns node]
$ns duplex-link $nx $nc ${bw_Gbps}Gb ${link_del_us}us DropTail
$ns queue-limit $nx $nc ${link_buf}

# Link Error Module between Switch and Client
set loss_module [new ErrorModel]
$loss_module unit pkt
$loss_module set rate_ $err_rate
set loss_random_variable [new RandomVariable/Uniform]
$loss_random_variable use-rng ${rng}
$loss_module ranvar ${loss_random_variable}
$loss_module drop-target [new Agent/Null]
$ns lossmodel $loss_module $nx $nc

#Create Servers (many)
for {set i 0} {$i < $svr_num} {incr i} {
    set n_($i) [$ns node]
    $ns duplex-link $nx $n_($i) ${bw_Gbps}Gb ${link_del_us}us DropTail
    $ns queue-limit $n_($i) $nx 1000
    set tcp_($i) [new Agent/TCP/Newreno]
    $tcp_($i) set fid_ $i
    $tcp_($i) attach-trace $tf
    $tcp_($i) trace maxseq_
    $tcp_($i) trace ack_
    set ftp_($i) [new Application/FTP]
    $ftp_($i) attach-agent $tcp_($i)
	$ftp_($i) set type_ FTP
    $ns attach-agent $n_($i) $tcp_($i)
    set snk_($i) [new Agent/TCPSink]
    $ns attach-agent $nc $snk_($i)
    $ns connect $tcp_($i) $snk_($i)

	# For FIN flags Emulation
	# If the value is over SRU_trans, the flow is finished.
	set prev_bytes($i) 0

    # Caluclate Delay (us)
    set del_us [expr $link_del_us * 2 + $SYN_del_us * $i \
					+ [$rng uniform 0 ${maxrand_SYN_del_us}]]

	# Establish new flow if possible
	if { [expr $cur_sum_wnd + $adv_wnd] <= $wnd_cap} {
		send_syn $i [expr 1.0 + $del_us * 0.000001]
		set cur_sum_wnd [expr $cur_sum_wnd + $adv_wnd]
		incr next_flowid
	}
}

$ns at 0.0 "debug"
$ns at 0.99 "check_trans"
$ns at 21.0 "finish"

proc update_link_del {} {
	global ns nx n_ link_del_us maxrand_link_del_us svr_num rng
	for {set i 0} {$i < $svr_num} {incr i} {
		$ns delay $nx $n_($i) [expr $link_del_us \
			   + [$rng uniform 0 ${maxrand_link_del_us}]]us duplex
	}
}

proc check_trans {} {
	global ns snk_ tcp_ Block_trans svr_num sub_slot_T
	global link_del_us tick wnd_cap whf zero_data_cnt
	global total_bytes_prev seed SRU
	global prev_bytes next_flowid SRU_trans cur_sum_wnd adv_wnd
	# 0.0001 = 100 us = 1 RTT
	set next_time 0.0001
	set now [$ns now]

	# check traffic, and if all data to be transmitted in each flow
	# then new flow is established
	# puts "$now: Server: 0, bytes: [$snk_(0) set bytes_]"
	set total_bytes 0
	for {set i 0} {$i < $svr_num} {incr i} {
		set total_bytes [expr $total_bytes + [$snk_($i) set bytes_]]
		if {$prev_bytes($i) < [$snk_($i) set bytes_]} {
			# This flow has new data
			if {[$snk_($i) set bytes_] >= ${SRU_trans}} {
				# This flow has been transmitted SRU first time only.
				set cur_sum_wnd [expr $cur_sum_wnd - $adv_wnd]
			}
			set prev_bytes($i) [$snk_($i) set bytes_]
		}
	}

	# If there are data to be transmitted and
	# there are enough window capacity then
	# new flows can be established.
	if {${next_flowid} < ${svr_num} && \
			[expr $cur_sum_wnd + $adv_wnd] <= $wnd_cap} {
		send_syn $next_flowid $now
		set cur_sum_wnd [expr $cur_sum_wnd + $adv_wnd]
		incr next_flowid
	}


    if {$total_bytes >= $Block_trans} {
		# All SRU is transmitted.
		if {$total_bytes == $Block_trans} {
			# Finish in just.
		} else {
			# Unnecessary Retransmit is exist.
		}
		flush stdout
		$ns at [expr $now + 1] "finish"
	}

    update_link_del

	if {$total_bytes - $total_bytes_prev > 0} {
		# There is some new transmitted data
		set zero_data_cnt 0
	} else {
		# There is not any new transmitted data
		if {$total_bytes >= $Block_trans} {
			# This calm period is not an incast affect.
			set zero_data_cnt 0
		} else {
			# This calm period may be an incast affect
			# because data to be transmitted is exist.
			incr zero_data_cnt
		}
	}

	# update total_bytes_prev
	set total_bytes_prev $total_bytes

	# There is not exist new data/ack traffic in 4RTT
	# so that means retransmission timeout will occur soon.
	if {$zero_data_cnt == 4 && $now > 1} {
		puts $whf "1\t${wnd_cap}\t${svr_num}\t${SRU}\t${seed}"
	}





	$ns at [expr $now + $next_time] "check_trans"
}

proc debug {} {
    global ns
    set next_time 1.0
    set now [$ns now]
    puts -nonewline "$now."
    flush stdout
    $ns at [expr $now+$next_time] "debug"
}

#Run the simulation
$ns run
