#!/usr/bin/perl -w

#$ARGV[0] tcp version

#$ARGV[1] queue management scheme 

#$ARGV[2] rwnd size

#$ARGV[3] server number

#$ARGV[4] link dela
my $ftpNumber=$ARGV[5];
my $telnetNumber=$ARGV[6];
my $telnetInterval=$ARGV[7];



open(INTrace,"$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSwitch.tr") || die "cannot open the file queueSwitch.tr at $!";


for($i=0;$i<$ARGV[3];$i++)
{
	open($OUT3[$i],">Delay$i.tr") || die "cannot open the file at $!";
}

@highestPacketID=(0) x $ARGV[3]; 

my @startTime;
my @delay;

for($i=0;$i<$ARGV[3];$i++)
{
	for($j=0;$j<1000000;$j++)
	{
		$startTime[$i][$j]=-1;
		$delay[$i][$j]=-1;
	}
}


@lostPackets=(0) x $ARGV[3]; 
@averageDelay=(0) x $ARGV[3];
@bornPackets=(0) x $ARGV[3];

if($ARGV[1] eq "DropTail")
{
	$queueSizePacket=0;
	$queueSizeByte=0;
	$fname=sprintf(">$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSize%d-%d.tr",$ARGV[3],$ARGV[3]+1);
	open($OUT4,$fname) || die "cannot open the file at $!";
}
elsif($ARGV[1] eq "FQ") {
	@queueSizePacket=(0) x $ARGV[3];
	@queueSizeByte=(0) x $ARGV[3];
	for($i=0;$i<$ARGV[3];$i++)
	{
		$fname=sprintf(">$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSize%d-%d.tr",$i,$ARGV[3]+1);
		open($OUT4[$i],$fname) || die "cannot open the file at $!";
	}
}
else {
	die "cannot deal with queueing management scheme $ARGV[1]  $!";
}

#=head;
while($line=<INTrace>)
{
	#print STDOUT "test!\n";
	@trace=split(" ",$line);
	$packetSize=$trace[5];
	$srcNode=$trace[2];
	$dstNode=$trace[3];
	@srcAddrs=split('\.',$trace[8]);
	@dstAddrs=split('\.',$trace[9]);
	$packetNumber=$trace[10];
	if(($trace[0] eq 'd') && ($dstNode eq $ARGV[3]+1))
	{
		$lostPackets[$srcAddrs[0]]=$lostPackets[$srcAddrs[0]]+1;
		if($ARGV[1] eq "DropTail")
		{
			$queueSizePacket=$queueSizePacket-1;
			$queueSizeByte=$queueSizeByte-$packetSize;
		}
		elsif($ARGV[1] eq "FQ")	{
			$queueSizePacket[$srcAddrs[0]]=$queueSizePacket[$srcAddrs[0]]-1;
			$queueSizeByte[$srcAddrs[0]]=$queueSizeByte[$srcAddrs[0]]-$packetSize;
		}
	}

	if($trace[0] eq '+')
	{
		$bornPackets[$srcAddrs[0]]=$bornPackets[$srcAddrs[0]]+1;
		if($ARGV[1] eq "DropTail")
		{
			$queueSizePacket=$queueSizePacket+1;
			$queueSizeByte=$queueSizeByte+$packetSize;
			#if($srcAddrs[0]<$telnetNumber)
			#{
				$outTemp=$OUT4;
				print $outTemp "$trace[1] $queueSizePacket\n";
			#}
		}
		elsif($ARGV[1] eq "FQ") {
			$queueSizePacket[$srcAddrs[0]]=$queueSizePacket[$srcAddrs[0]]+1;
			$queueSizeByte[$srcAddrs[0]]=$queueSizeByte[$srcAddrs[0]]+$packetSize;
			#if($srcAddrs[0]<$telnetNumber)
			#{
				$outTemp=$OUT4[$srcAddrs[0]];
				print $outTemp "$trace[1] $queueSizePacket[$srcAddrs[0]]\n";
			#}
		}
	}

	if($trace[0] eq '-')
	{
		if($ARGV[1] eq "DropTail")
		{
			$queueSizePacket=$queueSizePacket-1;
			$queueSizeByte=$queueSizeByte-$packetSize;
		}
		elsif($ARGV[1] eq "FQ")	{
			$queueSizePacket[$srcAddrs[0]]=$queueSizePacket[$srcAddrs[0]]-1;
			$queueSizeByte[$srcAddrs[0]]=$queueSizeByte[$srcAddrs[0]]-$packetSize;
		}
	}
	
	if($srcAddrs[0]!=$ARGV[3]+1)
	{
		if($packetNumber>$highestPacketID[$srcAddrs[0]])
		{
			$highestPacketID[$srcAddrs[0]]=$packetNumber;
		}

		if($startTime[$srcAddrs[0]][$packetNumber]==-1)
		{
			$startTime[$srcAddrs[0]][$packetNumber]=$trace[1];
		}

		if(($trace[0] eq 'r') && ($dstNode eq $ARGV[3]+1))
		{
			$delay[$srcAddrs[0]][$packetNumber]=$trace[1]-$startTime[$srcAddrs[0]][$packetNumber];
			
			$averageDelay[$srcAddrs[0]]=$averageDelay[$srcAddrs[0]]+$delay[$srcAddrs[0]][$packetNumber];
			#if($srcAddrs[0]<$telnetNumber)
			#{
				$outTemp=$OUT3[$srcAddrs[0]];
				print $outTemp "$trace[1] $delay[$srcAddrs[0]][$packetNumber]\n";
			#}
		}
	}
}

for($i=0;$i<$ARGV[3];$i++)
{
	printf("Packets born of Node%d-Node%d :%d\n",$i,($ARGV[3]+1),$bornPackets[$i]);
}

#=head;
for($i=0;$i<$ARGV[3];$i++)
{
	printf("Pakcet loss rate of Node%d-Node%d :%f\n",$i,($ARGV[3]+1),$lostPackets[$i]/$bornPackets[$i]);
}

for($i=0;$i<$ARGV[3];$i++)
{
	printf("Average packet delay of Node%d-Node%d :%f\n",$i,($ARGV[3]+1),$averageDelay[$i]/$bornPackets[$i]);
}
#=cut
