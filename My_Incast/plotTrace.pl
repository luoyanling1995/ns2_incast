#!/usr/bin/perl -w

use strict;


#$ARGV[0] tcp version

#$ARGV[1] queue management scheme 

#$ARGV[2] rwnd size

#$ARGV[3] server number

#$ARGV[4] link delay

system("perl TraceProcess.pl $ARGV[0] $ARGV[1] $ARGV[2] $ARGV[3] $ARGV[4]");


my $PLOT;
my $file;
open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";

#mytics
#set mytics 5
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]_TCP_cwnd.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "cwnd (MSS)"
filenames(n)=sprintf("$ARGV[0]-$ARGV[1]-$ARGV[2]-cwnd%d.tr",n) 
curvetitles(n)=sprintf("Flow-%d",n)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;

open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]_TCP_Throughput.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "throughput (bps)"
filenames(n)=sprintf("Throughput%d.tr",n) 
curvetitles(n)=sprintf("Flow-%d",n)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;

open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]_TCP_Sending_Rate.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "sending rate (bps)"
filenames(n)=sprintf("SendingRate%d.tr",n) 
curvetitles(n)=sprintf("Flow-%d",n)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;

open ($PLOT, "|gnuplot") or die "error: gnuplot not found!";
print $PLOT <<EOPLOT;

set terminal postscript color
set output "$ARGV[0]-$ARGV[1]-$ARGV[2]_TCP_RTT.ps"
set title "$ARGV[0]-$ARGV[1]-$ARGV[2]"
set grid ytics 
set xlabel "time (s)"
set ylabel "RTT (s)"
filenames(n)=sprintf("Delay%d.tr",n) 
curvetitles(n)=sprintf("Flow-%d",n)
plot for [i=0:$ARGV[3]-1] filenames(i) with line linewidth 3 title curvetitles(i)
EOPLOT

close $PLOT;

`rm Delay*.tr Throughput*.tr SendingRate*.tr`;
