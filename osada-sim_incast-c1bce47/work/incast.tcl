# Basic Incast Simulation
# Check Args
if {$argc != 5} {
  puts "Usage: ns incast <srv_num> <adv_win-pkt> <SRU-KB> <link_buf-pkt> <seed>"
  exit 1
}

#################################################################
# Argments
# ServerNum: $argv(0)
set svr_num [lindex $argv 0]
# Advertised Window size (pkt): $argv(1)
set adv_win [lindex $argv 1]
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
# Maximum Random Link Delay: 0--maxrand (us)
set maxrand_link_del_us 20

# SYN Interval Delay (us) for each Request
set SYN_del_us 0
## For Aggressive Optimization for Goodput (may cause incast)
# set SYN_del_us [expr int(${SRU} * 8 / (${bw_Gbps} * pow(10, 9)) * pow(10, 6))]
## For Conservative Optimization for Goodput (never cause incast)
# set SYN_del_us [expr int(${SRU} * 8 / (${bw_Gbps} * pow(10, 9)) * pow(10, 6)\
#   + ${link_del_us} * 4 * (1 + \
#   (log10( ${link_del_us} * 4 * pow(10, -6) * ${bw_Gbps} * pow(10, 9) \
#   / (1500 * 8) ) / log10(2))))]

# Maximum Random SYN Delay: 0--maxrand (us)
set maxrand_SYN_del_us 0

# Total Size of All Servers SRU with TCP/IP Header and Handshake
set Block_trans [expr ((int($SRU / 1460) + 1)* 1500 + 40) * $svr_num]

# Link Error Rate (Unit:pkt) 0.001 = 0.1% (a loss in 1000 pkt)
# set err_rate 0.001
set err_rate 0

#############################################
# Random Model
set rng [new RNG]
# seed 0 equal to current OS time (UTC)
# so seed should be more than 1 for repeatability
$rng seed [expr ${seed} * ${svr_num} + 1]

#################################################################
# Tracing Message
puts -nonewline "Server: $svr_num, win: ${adv_win}pkt, "
puts -nonewline "SRU: [lindex $argv 2]KB, link_buf: ${link_buf}pkt, "
puts "Seed: $seed, "
puts -nonewline "Block_trans: ${Block_trans}B, "
puts -nonewline "RTT: [expr $link_del_us * 4]us, "
puts -nonewline "RTT_rand: ${maxrand_link_del_us}us, "
puts "SYN_del: ${SYN_del_us}-[expr $SYN_del_us + $maxrand_SYN_del_us]us"

Agent/TCP set trace_all_oneline_ true
Agent/TCP set packetSize_ 1460
Agent/TCP set window_ $adv_win
Agent/TCP set singledup_ 0 ;      # 0: Disabled Limited Transmit
Agent/TCP set tcpTick_ 0.0000001 ;  # 100ns (default 0.01: 10ms)


#Open the ns trace file
set nf [open out.ns w]
$ns trace-all $nf
set ef [open out.et w]
$ns eventtrace-all $ef
set tf [open out.tcp w]
# For Queue Monitoring
# set q_trans [open queue_trans.ns w]

proc finish {} {
	global ns nf ef tf
	# For Queue Monitoring
	# global q_trans
	$ns flush-trace
	close $nf
	close $tf
	close $ef
	# close $q_trans
	puts "Done."
	exit 0
}

#Create two nodes
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

    # Caluclate Delay (us)
    set del_us [expr $link_del_us * 2 + $SYN_del_us * $i \
					+ [$rng uniform 0 ${maxrand_SYN_del_us}]]

 	$ns at [expr 1.0 + $del_us * 0.000001] "$ftp_($i) send $SRU"
}
$ns at 0.0 "debug"
$ns at 0.99 "check_trans"
$ns at 21.0 "finish"

# For Queue Monitoring
# set q_mon [$ns monitor-queue $nx $nc [open queue_mon.ns w] 0.0001]
# [$ns link $nx $nc] queue-sample-timeout

proc update_link_del {} {
	global ns nx n_ link_del_us maxrand_link_del_us svr_num rng
	for {set i 0} {$i < $svr_num} {incr i} {
		$ns delay $nx $n_($i) [expr $link_del_us \
			   + [$rng uniform 0 ${maxrand_link_del_us}]]us duplex
	}
}

proc check_trans {} {
	global ns Block_trans svr_num snk_
	# 0.0001 = 100 us = 1 RTT
	set time 0.0001
	set now [$ns now]

	# check traffic to each TCP sink agent
	# puts "$now: Server: 0, bytes: [$snk_(0) set bytes_]"
	set total_bytes 0
	for {set i 0} {$i < $svr_num} {incr i} {
		set total_bytes [expr $total_bytes + [$snk_($i) set bytes_]]
	}

	# Is any data to be transmitted?
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

	# For Queue Monitoring
	# $q_mon instvar parrivals_ pdepartures_ bdrops_ bdepartures_ pdrops_
    # puts $q_trans "$now $bdepartures_"

	# For update_link
    update_link_del

	$ns at [expr $now+$time] "check_trans"
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
