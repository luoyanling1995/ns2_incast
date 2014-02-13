if { $argc !=5 } {
       puts "Usage:ns tcpversion.tcl tcpversion QueueingManagement_scheme rwnd_size serverNumber linkDelay(ms)"
       exit
}
 
set par1 [lindex $argv 0]
#tcp version

set par2 [lindex $argv 1]
#queue management scheme 

set par3 [lindex $argv 2]
#rwnd size

set serverNumber [lindex $argv 3]
#serverNumber  how many servers connceted to one client

set linkDelay [lindex $argv 4]

set ns [new Simulator]
#打开一个trace文件，用来记录数据报传送的过程
set nd [open $par1-$par2-$par3-$serverNumber.tr w]
$ns trace-all $nd
#打开一个文件用来记录cwnd变化情况

for {set i 0} {$i<$serverNumber} {incr i} {
	set f($i) [open $par1-$par2-$par3-cwnd$i.tr w]
}


set timeLength 10

#定义一个结束的程序
proc finish {} {
       global ns f nd tcp timeLength tcpsink serverNumber
       set totalThroughput 0
       for {set i 0} {$i<$serverNumber} {incr i} {
       		set throughput [expr [$tcp($i) set ack_]*([$tcp($i) set packetSize_]+40)*8/1000/$timeLength]
		puts [format "average throughput of Node%d-Node%d :%.1f Kbps" \ $i $serverNumber $throughput]
		set totalThroughput [expr {$totalThroughput+$throughput}]
	}
	puts [format "output link load is :%.1f Mbps" [expr $totalThroughput/1000]]
	$ns flush-trace
	close $nd
	for {set i 0} {$i<$serverNumber} {incr i} {
		close $f($i)
		}
	exit 0
}
#定义一个记录的程序
proc record {} {
       global ns tcp f serverNumber
       set now [$ns now]
       for {set i 0} {$i<$serverNumber} {incr i} {
       		puts $f($i) "$now [$tcp($i) set cwnd_]"
	}
       $ns at [expr $now+1/1e2] "record"
}
 
#产生传送结点，路由器r1和r2和接收结点
for {set i 0} {$i<$serverNumber} {incr i} {
	set n($i) [$ns node]
}
set r0 [$ns node]
set n($serverNumber) [$ns node]
#建立链路
for {set i 0} {$i<$serverNumber} {incr i} {
	$ns duplex-link $n($i) $r0 20Mb [expr $linkDelay*1E-3]s DropTail
}
$ns duplex-link $r0 $n($serverNumber) 20Mb 1ms $par2
 
#设置队列长度为18个封包大小
set queueLink 18
set queueSwitch 18
for {set i 0} {$i<$serverNumber} {incr i} {
	$ns queue-limit $n($i) $r0 $queueLink
}
$ns queue-limit $r0 $n($serverNumber) $queueSwitch

Agent/TCP set window_ $par3
Agent/TCP set packetSize_ 1000
Agent/TCP set tcpTick_ 1e-4
 
#根据用户的设置，指定TCP版本，并建立相应的Agent
if { $par1 == "Tahoe" } {
	for {set i 0} {$i<$serverNumber} {incr i} {
	       	set tcp($i) [new Agent/TCP]
	       	set tcpsink($i) [new Agent/TCPSink]
	}
} elseif { $par1 == "Reno" } {
	for {set i 0} {$i<$serverNumber} {incr i} {
	       	set tcp($i) [new Agent/TCP/Reno]
	       	set tcpsink($i) [new Agent/TCPSink]
	}
} elseif {$par1=="Newreno"} {
	for {set i 0} {$i<$serverNumber} {incr i} {
	       	set tcp($i) [new Agent/TCP/Newreno]
	       	set tcpsink($i) [new Agent/TCPSink]
	}
} elseif {$par1 =="Sack"} {
	for {set i 0} {$i<$serverNumber} {incr i} {
	       	set tcp($i) [new Agent/TCP/Sack1]
	       	set tcpsink($i) [new Agent/TCPSink/Sack1]
	}
}


for {set i 0} {$i<$serverNumber} {incr i} {
	$ns attach-agent $n($i) $tcp($i)
	$ns attach-agent $n($serverNumber) $tcpsink($i)
}

for {set i 0} {$i<$serverNumber} {incr i} {
	$ns connect $tcp($i) $tcpsink($i)
}

 
#建立FTP应用程序
for {set i 0} {$i<$serverNumber} {incr i} {
	set ftp($i) [new Application/FTP]
	$ftp($i) attach-agent $tcp($i)
}

for {set i 0} {$i<$serverNumber} {incr i} {
	$ns at 0.0 "$ftp($i) start"
}
for {set i 0} {$i<$serverNumber} {incr i} {
	$ns at $timeLength "$ftp($i) stop"
}

#在0.0s时调用record来记录TCP的cwnd 变化情况
$ns at 0.0 "record"
$ns at $timeLength "finish"
$ns run
