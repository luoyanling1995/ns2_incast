# Check Args
if {$argc != 5} {
  puts "Usage: ns incast <srv_num> <adv_win-pkt> <SRU-KB> <link_buf-pkt> <seed>"
  exit 1
}

# Create a simulator object
set ns [new Simulator]

# Link Delay (us)
set link_del_us 25
# Maximum Random Link Delay: 0--maxrand (us)
set maxrand_link_del_us 20

# SYN Interval Delay (us) for each Request
set SYN_del_us 0
# Maximum Random SYN Delay: 0--maxrand (us)
set maxrand_SYN_del_us 0

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

# Total Size of All Servers SRU with TCP/IP Header and Handshake
set Block_trans [expr ((int($SRU / 1460) + 1)* 1500 + 40) * $svr_num]
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
Agent/TCP set singledup_ 0 ;# 0: Disabled Limited Transmit

# NoDelayedACK
Agent/TCPSink/IncastAvoidance set interval_ 0ms
# Incast Avoidance Ack
Agent/TCPSink/IncastAvoidance set ia_ack_interval_ 500us

#Open the ns trace file
set nf [open out.ns w]
$ns trace-all $nf
set ef [open out.et w]
$ns eventtrace-all $ef
set tf [open out.tcp w]
set q_trans [open queue_trans.ns w]

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

#Create two nodes
set nx [$ns node]
set nc [$ns node]
$ns duplex-link $nx $nc 1Gb ${link_del_us}us DropTail
$ns queue-limit $nx $nc ${link_buf}

for {set i 0} {$i < $svr_num} {incr i} {
    set n_($i) [$ns node]
    $ns duplex-link $nx $n_($i) 1Gb ${link_del_us}us DropTail
    set tcp_($i) [new Agent/TCP/Newreno]
    $tcp_($i) set fid_ $i
    $tcp_($i) attach-trace $tf
    $tcp_($i) trace maxseq_
    $tcp_($i) trace ack_
    set ftp_($i) [new Application/FTP]
    $ftp_($i) attach-agent $tcp_($i)
	$ftp_($i) set type_ FTP
    $ns attach-agent $n_($i) $tcp_($i)
    set snk_($i) [new Agent/TCPSink/IncastAvoidance]
    $snk_($i) set ia_ack_interval_ [expr 2 + int(10 * rand())]ms
    $ns attach-agent $nc $snk_($i)
    $ns connect $tcp_($i) $snk_($i)

    # Caluclate Delay (us)
    set del_us [expr $link_del_us * 2 + $SYN_del_us * $i \
                            + int($maxrand_SYN_del_us * rand())]

 	$ns at [expr 1.0 + $del_us * 0.000001] "$ftp_($i) send $SRU"
}
$ns at 0.0 "debug"
$ns at 0.99 "check_trans"
$ns at 21.0 "finish"

set q_mon [$ns monitor-queue $nx $nc [open queue_mon.ns w] 0.0001]
[$ns link $nx $nc] queue-sample-timeout


# rand() returns 0..0.999999 (not include 1)
proc update_link_del {} {
	global ns nx n_ link_del_us maxrand_link_del_us svr_num
	for {set i 0} {$i < $svr_num} {incr i} {
		$ns delay $nx $n_($i) [expr $link_del_us \
			   + { int($maxrand_link_del_us * rand()) }]us duplex
	}
}

proc check_trans {} {
	global ns q_mon Block_trans q_trans
	set time 0.0001
	set now [$ns now]
	$q_mon instvar parrivals_ pdepartures_ bdrops_ bdepartures_ pdrops_
    puts $q_trans "$now $bdepartures_"
    if {$bdepartures_ >= $Block_trans} {
		# All SRU is transmitted.
		if {$bdepartures_ == $Block_trans} {
			# puts -nonewline "So."
		} else {
#			puts -nonewline "Sx."
		}
		flush stdout
        set bdepartures_ 0
		$ns at [expr $now + 1] "finish"
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
