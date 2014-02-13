#!/bin/sh

NOW=`date '+%Y%m%d_%H%M%S'`

SVR_NUM=64
SRU_SIZE="64 128 256"
ADV_WIN="2"
LINK_BUF="120"
REPEAT="20"

SCRIPT="incast-ictcp.tcl"
OUTPUT="goodput.${NOW}.dat"
NS_OUT="out.ns"
ET_OUT="out.et"
TCP_OUT="out.tcp"
GP_OUT="gp.dat"
C_NODE_ID=1
X_NODE_ID=0
TIME_GRAIN=1.0

NS_CMD="ns"
GP_CMD="./a.out"
TAIL_1_CMD="tail -1"
SEQ_CMD="jot"
# in Linux
# SEQ_CMD="seq"


cat /dev/null > $OUTPUT

# Output Data Index (line 1)
for SRU in $SRU_SIZE
  do
  printf "\tGP_${SRU}KB\tRTX_${SRU}KB\tWND_${SRU}" >> $OUTPUT
done
echo "" >> $OUTPUT

# Start Simulations
#for SVR in `$SEQ_CMD $SVR_NUM`
for SVR in 2 `$SEQ_CMD 16 4 $SVR_NUM`
#for SVR in 2 3 4
do
  printf "$SVR\t" >> $OUTPUT
  for SRU in $SRU_SIZE
  do
    cat /dev/null > $GP_OUT
    i=0
    while [ $i -lt $REPEAT ]
    do
      # Exec Simulation ($i = random seed)
	  $NS_CMD $SCRIPT $SVR $ADV_WIN $SRU $LINK_BUF $i
	  # Calculate Goodput and Summary
	  $GP_CMD $NS_OUT $ET_OUT $C_NODE_ID $TIME_GRAIN | $TAIL_1_CMD >> $GP_OUT
	  i=`expr $i + 1`
    done
    # Caluclate Average Goodput
	awk '{sum_tp += $1; is_rto += $2;} \
         END {printf sum_tp/NR "\t" is_rto/NR "\t"}' $GP_OUT >> $OUTPUT
	# Write Window size (Last one)
	$TAIL_1_CMD $TCP_OUT | awk '{printf $34 "\t"}' >> $OUTPUT
  done
  echo "" >> $OUTPUT
done
