#!/usr/bin/perl -w

use strict;


#$ARGV[0] tcp version

#$ARGV[1] queue management scheme 

#$ARGV[2] rwnd size

#$ARGV[3] server number

#$ARGV[4] link delay

my $ftpNumber=$ARGV[5];
my $telnetNumber=$ARGV[6];
my $telnetInterval=$ARGV[7];

system("perl TraceQueueSwitchProcess.pl $ARGV[0] $ARGV[1] $ARGV[2] $ARGV[3] $ARGV[4] $ARGV[5] $ARGV[6] $ARGV[7]");


my $PLOT;
my $file;
open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";

print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSwitch_Delay.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "delay (s)"
filenames(n)=sprintf("Delay%d.tr",n) 
curvetitles(n)=sprintf("Flow-%d",n)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;

open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";

if($ARGV[1] eq "DropTail"){
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSwitch_Size.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "queueSize (packets)"
filenames=sprintf("$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSize$ARGV[3]-%d.tr",$ARGV[3]+1) 
curvetitles=sprintf("Flow%d-%d",$ARGV[3],$ARGV[3]+1)
plot filenames with line linewidth 3 title curvetitles
EOPLOT

close $PLOT;
}
elsif($ARGV[1] eq "FQ") {
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSwitch_Size.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "queueSize (packets)"
filenames(n)=sprintf("$ARGV[0]-$ARGV[1]-$ARGV[2]-queueSize%d-%d.tr",n,$ARGV[3]+1) 
curvetitles(n)=sprintf("Flow%d-%d",n,$ARGV[3]+1)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;
}

