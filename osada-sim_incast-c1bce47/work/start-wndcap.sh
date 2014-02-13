#!/bin/sh

NOW=`date '+%Y%m%d_%H%M%S'`

SVR_NUM=64
# Unit: KB
SRU_SIZE="64 128 256"
# Unit: pkt (=1500B)
INIT_WND_CAP="20"
LINK_BUF="40"
REPEAT="20"

SCRIPT="incast-wndcap.tcl"
OUTPUT="goodput.${NOW}.txt"
NS_OUT="out.ns"
ET_OUT="out.et"
TCP_OUT="out.tcp"
GP_OUT="gp.dat"
WND_HIS="window_history"
C_NODE_ID=1
X_NODE_ID=0
TIME_GRAIN=1.0

NS_CMD="ns"
GP_CMD="./a.out"
TAIL_1_CMD="tail -1"
SEQ_CMD="jot"
# in Linux
# SEQ_CMD="seq"

# Constant value
WND_CAP_MAX=99999

# Initialize Output and History files
cat /dev/null > $OUTPUT
cat /dev/null > $WND_HIS

# Output Data Index (line 1)
for SRU in $SRU_SIZE
  do
  printf "\tGP_${SRU}KB\tRTX_${SRU}KB\tWND_${SRU}" >> $OUTPUT
done
echo "" >> $OUTPUT

# Start Simulations
# for SVR in `$SEQ_CMD $SVR_NUM`
for SVR in 2 `$SEQ_CMD 16 4 $SVR_NUM`
do
  printf "$SVR\t" >> $OUTPUT
  # Calculate ADV_WIN form Initial WND_CAP
  WND_CAP=${INIT_WND_CAP}

  for SRU in $SRU_SIZE
  do
    cat /dev/null > $GP_OUT
    i=0
    while [ $i -lt $REPEAT ]
	do
      # Exec Simulation ($i = random seed)
	  $NS_CMD $SCRIPT $SVR $WND_CAP $SRU $LINK_BUF $i
	  # Calculate Goodput and Summary
	  $GP_CMD $NS_OUT $ET_OUT $C_NODE_ID $TIME_GRAIN | $TAIL_1_CMD >> $GP_OUT

	  # Calculate New Window Capacity as large as not causing incast
	  # First, Find the smallest number of causing incast.
	  # grep '^1' means SELECT lines of incast information
	  # cut -f 2 means get window capacity only
	  # sort -n and head -1 means get minimum value
	  WND_CAP_INC_MIN=`grep '^1' $WND_HIS | cut -f 2 | sort -n | head -1`
	  if [ -z "$WND_CAP_INC_MIN" ]; then
		 WND_CAP_INC_MIN=$WND_CAP_MAX
	  fi

	  # Second, Find the largest number as large as cot causing incast
	  WND_CAP=0
	  hl_size=`wc -l $WND_HIS | awk '{print $1}'`
	  hl=1
	  while [ $hl -le $hl_size ]
	  do
		WND_CAP=`grep '^0' $WND_HIS | cut -f 2 |\
            sort -n -r | head -$hl | tail -1`
		if [ -z "$WND_CAP" ]; then
			# the case that there are no candidates
			WND_CAP=0
			break
		elif [ $WND_CAP -lt $WND_CAP_INC_MIN ]; then
			# the case that WND_CAP is candidate!
			break
		else
			# the case that WND_CAP is grater than Incast Capacity
			# search next value (by while loop)
			WND_CAP=0
		fi
		hl=`expr $hl + 1`
	  done

	  # Finally, Optimize WND_CAP using the history
	  if [ $WND_CAP -eq 0 ]; then
		  if [ $WND_CAP_INC_MIN -eq $WND_CAP_MAX ]; then
			  # the case that INIT_WND_CAP gurantees not to cause incast
			  WND_CAP=$INIT_WND_CAP
		  else
			  # the case that there are some learnd value causing incast
			  WND_CAP=`expr $WND_CAP_INC_MIN / 2`
		  fi
	  fi

	  if [ `expr $WND_CAP + $SVR` -le $WND_CAP_INC_MIN ]; then
		  WND_CAP=`expr $WND_CAP + $SVR`
	  fi

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

date
