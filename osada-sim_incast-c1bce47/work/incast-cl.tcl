# Connection Limit
# Check Args
if {$argc != 5} {
  puts "Usage: ns incast <srv_num> <adv_win-pkt> <SRU-KB> <link_buf-pkt> <seed>"
  exit 1
}

# Create a simulator object
set ns [new Simulator]

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
expr srand($seed * $svr_num)

############################################################################
# Variable Settings
# Link Delay (us)
set link_del_us 25
# Maximum Random Link Delay: 0--maxrand (us)
set maxrand_link_del_us 20
# SYN Interval Delay (us) for each Request
set SYN_del_us 0
# Maximum Random SYN Delay: 0--maxrand (us)
set maxrand_SYN_del_us 0

# Total Size of All Servers SRU with TCP/IP Header and Handshake
set SRU_trans [expr (int($SRU / 1460) + 1) * 1500 + 40]
set Block_trans [expr ${SRU_trans} * ${svr_num}]

# the number of connection limit
# BDP: 1 * pow(10, 9) * $link_del_us * 4 * pow(10, -6)
# MSS: 1500 (fixed)
set con_lim [expr (1 * pow(10, 9) * ${link_del_us} * 4 * pow(10, -6) \
					   + ${link_buf} * 1500 * 8) / (${adv_win} * 1500 * 8)]
#set con_lim [expr (${link_buf} * 1500 * 8) / (${adv_win} * 1500 * 8)]
set next_flowid 0


############################################################################
# Trace Messages
puts -nonewline "Server: $svr_num, win: ${adv_win}pkt, "
puts -nonewline "SRU: [lindex $argv 2]KB, link_buf: ${link_buf}pkt, "
puts "Seed: $seed, "
puts -nonewline "RTT: [expr $link_del_us * 4]-"
puts -nonewline "[expr $link_del_us * 4 + $maxrand_link_del_us]us, "
puts -nonewline "SYN_del: ${SYN_del_us}-"
puts -nonewline "[expr $SYN_del_us + $maxrand_SYN_del_us]us, "
puts -nonewline "Block_trans: ${Block_trans}B, "
puts -nonewline [format "con_lim: %3f\n" ${con_lim}]

Agent/TCP set trace_all_oneline_ true
Agent/TCP set packetSize_ 1460
Agent/TCP set window_ $adv_win
Agent/TCP set singledup_ 0 ;      # 0: Disabled Limited Transmit
Agent/TCP set tcpTick_ 0.0000001 ;  # 100ns (default 0.01: 10ms)
###########################################################################

# Check connection limit
if {$con_lim < 1} {
	puts "connection limit is too small"
	set con_lim 1
}


###########################################################################
# Senario
#Open the ns trace file
set nf [open out.ns w]
$ns trace-all $nf
set ef [open out.et w]
$ns eventtrace-all $ef
set tf [open out.tcp w]
set q_trans [open queue_trans.ns w]

# finish
proc finish {} {
        global ns nf ef tf q_trans
        $ns flush-trace
        close $nf
        close $tf
    	close $ef
        close $q_trans
        puts "Done."
        exit 0
}

# send syn packet
proc send_syn {flowid time} {
	global ns link_del_us ftp_ SRU
	$ns at [expr $time + ${link_del_us} * 2 * 0.000001] \
		"$ftp_($flowid) send $SRU"
}


#Create two nodes
set nx [$ns node]
set nc [$ns node]
$ns duplex-link $nx $nc 1Gb ${link_del_us}us DropTail
$ns queue-limit $nx $nc ${link_buf}

for {set i 0} {$i < $svr_num} {incr i} {
    set n_($i) [$ns node]
    $ns duplex-link $nx $n_($i) 1Gb ${link_del_us}us DropTail
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

	set prev_bytes($i) 0
	
	if {$i <= [expr ${con_lim} - 1]} {
		send_syn $i [expr 1.0 + ($SYN_del_us * $i \
				+ int($maxrand_SYN_del_us * rand())) * 0.000001]
		incr next_flowid
	}
}

$ns at 0.0 "debug"
$ns at 0.99 "check_trans"
$ns at 21.0 "finish"

set q_mon [$ns monitor-queue $nx $nc [open queue_mon.ns w] 0.0001]
[$ns link $nx $nc] queue-sample-timeout

# rand() returns 0..0.999999 (not in 1)
proc update_link_del {} {
	global ns nx n_ link_del_us maxrand_link_del_us svr_num
	for {set i 0} {$i < $svr_num} {incr i} {
		$ns delay $nx $n_($i) [expr $link_del_us \
			   + { int($maxrand_link_del_us * rand()) }]us duplex
	}
}

proc check_trans {} {
	global ns q_mon Block_trans q_trans svr_num snk_
	global prev_bytes next_flowid SRU_trans
	set time 0.0001
	set now [$ns now]
	$q_mon instvar parrivals_ pdepartures_ bdrops_ bdepartures_ pdrops_
    puts $q_trans "$now $bdepartures_"
    if {$bdepartures_ >= $Block_trans} {
		# All SRU is transmitted.
		if {$bdepartures_ == $Block_trans} {
			# puts -nonewline "So."
		} else {
			puts -nonewline "Sx."
		}
		flush stdout
        set bdepartures_ 0
		$ns at [expr $now + 1] "finish"
	}

	for {set i 0} {$i < $svr_num} {incr i} {
		if {$prev_bytes($i) < [$snk_($i) set bytes_]} {
			# This flow has new data
			if {[$snk_($i) set bytes_] >= ${SRU_trans}} {
				# This flow has been transmitted SRU first time.
				if {${next_flowid} < ${svr_num}} {
					send_syn $next_flowid $now
					incr next_flowid
				}
			}
			set prev_bytes($i) [$snk_($i) set bytes_]
		}
	}

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
