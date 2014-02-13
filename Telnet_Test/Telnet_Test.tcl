if { $argc !=8 } {
       puts "Usage:ns tcpversion.tcl tcpversion QueueingManagement_scheme rwnd_size serverNumber linkDelay(ms) ftpNumber telnetNumber telnetInterval(s)"
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

set ftpNumber [lindex $argv 5]

set telnetNumber [lindex $argv 6]

set telnetInterval [lindex $argv 7]

if { [expr $telnetNumber+$ftpNumber] !=$serverNumber } {
       puts "Usage: telnetNumber+ftpNumber != serverNumber"
       exit
}

set ns [new Simulator]
#打开一个trace文件，用来记录数据报传送的过程
set nd [open $par1-$par2-$par3-$serverNumber.tr w]
$ns trace-all $nd
#打开一个文件用来记录cwnd变化情况

for {set i 0} {$i<$serverNumber} {incr i} {
	set f($i) [open $par1-$par2-$par3-cwnd$i.tr w]
}




set timeLength 1E2

#定义一个结束的程序
proc finish {} {
       global ns f nd tcp timeLength tcpsink serverNumber
       set totalThroughput 0
       for {set i 0} {$i<$serverNumber} {incr i} {
       		set throughput [expr [$tcp($i) set ack_]*([$tcp($i) set packetSize_]+40)*8/1E3/$timeLength]
		puts [format "average throughput of Node%d-Node%d :%.1f Kbps" \ $i $serverNumber $throughput]
		set totalThroughput [expr {$totalThroughput+$throughput}]
	}
	puts [format "output link load is :%f Mbps" [expr $totalThroughput/1E3]]
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
$ns duplex-link $r0 $n($serverNumber) 20Mb [expr $linkDelay*1E-3]s $par2
 
set trace_file [open  "$par1-$par2-$par3-queueSwitch.tr"  w]

$ns  trace-queue  $r0  $n($serverNumber)   $trace_file 

set trace_file1 [open  "$par1-$par2-$par3-queue1.tr"  w]

$ns  trace-queue  $n(1)  $r0   $trace_file1 
 
#设置队列长度为18个封包大小
set queueLink 1000
set queueSwitch 30
for {set i 0} {$i<$serverNumber} {incr i} {
	$ns queue-limit $n($i) $r0 $queueLink
}
$ns queue-limit $r0 $n($serverNumber) $queueSwitch

Agent/TCP set window_ $par3
#Agent/TCP set maxrto_ 0.2
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

Application/Telnet set interval_ $telnetInterval
 
#建立telnet应用程序
for {set i 0} {$i<$telnetNumber} {incr i} {
	set telnet($i) [new Application/Telnet]
	$tcp($i) set packetSize_ 1000
	$telnet($i) attach-agent $tcp($i)
}

#建立FTP应用程序
for {set i 0} {$i<$ftpNumber} {incr i} {
	set ftp($i) [new Application/FTP]
	$tcp([expr $i+$telnetNumber]) set packetSize_ 1500
	$ftp($i) attach-agent $tcp([expr $i+$telnetNumber])
}

for {set i 0} {$i<$telnetNumber} {incr i} {
	$ns at 0.0 "$telnet($i) start"
	$ns at $timeLength "$telnet($i) stop"
}
for {set i 0} {$i<$ftpNumber} {incr i} {
	$ns at 0.0 "$ftp($i) start"
	$ns at $timeLength "$ftp($i) stop"
}

#在0.0s时调用record来记录TCP的cwnd 变化情况
$ns at 0.0 "record"
$ns at $timeLength "finish"
$ns run
