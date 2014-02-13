#!/usr/bin/perl -w

#$ARGV[0] tcp version

#$ARGV[1] queue management scheme 

#$ARGV[2] rwnd size

#$ARGV[3] server number

#$ARGV[4] link delay

open(INTrace,"<$ARGV[0]-$ARGV[1]-$ARGV[2]-$ARGV[3].tr");
for($i=0;$i<$ARGV[3];$i++)
{
	open($OUT1[$i],">Throughput$i.tr" || die "cannot open the file at $!");
}
for($i=0;$i<$ARGV[3];$i++)
{
	open($OUT2[$i],">SendingRate$i.tr" || die "cannot open the file at $!");
}

@receivedBytes=(0) x $ARGV[3]; 
@sentBytes=(0) x $ARGV[3];

for($i=0;$i<$ARGV[3];$i++)
{
	open($OUT3[$i],">Delay$i.tr" || die "cannot open the file at $!");
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

#=head;
while($line=<INTrace>)
{
	@trace=split(" ",$line);
	$packetSize=$trace[5];
	$srcNode=$trace[2];
	$dstNode=$trace[3];
	@srcAddrs=split('\.',$trace[8]);
	@dstAddrs=split('\.',$trace[9]);
	$packetNumber=$trace[10];
	if(($trace[0] eq 'r') && ($dstNode eq $ARGV[3]+1))
	{
		$receivedBytes[$srcAddrs[0]]=$receivedBytes[$srcAddrs[0]]+$packetSize;
		
		$currentThroughput=$receivedBytes[$srcAddrs[0]]*8/$trace[1];
		
		$outTemp=$OUT1[$srcAddrs[0]];
		print $outTemp "$trace[1] $currentThroughput\n";	
	}

	if(($trace[0] eq '+') && ($dstNode eq $ARGV[3]) && ($srcNode < $ARGV[3]))
	{
		$sentBytes[$srcAddrs[0]]=$sentBytes[$srcAddrs[0]]+$packetSize;
		if($trace[1] != 0)
		{
			$currentThroughput=$sentBytes[$srcAddrs[0]]*8/$trace[1];
			$outTemp=$OUT2[$srcAddrs[0]];
			print $outTemp "$trace[1] $currentThroughput\n";
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
			$delay[$srcAddrs[0]][$packetNumber]=$trace[1]-$startTime[$srcAddrs[0]][$packetNumber]+2*$ARGV[4]*1E-3;
			$outTemp=$OUT3[$srcAddrs[0]];
			print $outTemp "$trace[1] $delay[$srcAddrs[0]][$packetNumber]\n";
		}
	}
}
#=cut;
