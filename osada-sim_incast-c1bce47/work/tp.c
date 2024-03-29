/* gput.c: out.trを解析してスループット特性を計算する
 *         out.etを解析して再送タイムアウトの発生有無を確認する
 *   gput <trace file> <event trace file > <required node> <granlarity>
 *   (e.g.,) ./gput out.tr out.et 1 1.0 > goodput.dat
 *   last line output: <goodput>Mbps <isIncast> <transmitted bytes>Byte \
 *              <transmission time>s <first_recv_time>s <last_recv_time>s
 *   <isIncast>: 0 = fales (not incast); 1 = true (incast)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXFLOW 128
#define SW_NODE 0

typedef struct rcvd_t {
  int seqno;
  int flow_id;
  struct rcvd_t *next;
} rcvd_t;

rcvd_t head;

int isnew (int seqno, int flow_id)
{
  rcvd_t *rcvd = head.next;

  while ( rcvd ){
    if ( rcvd->seqno == seqno && rcvd->flow_id == flow_id ) return 0;
    rcvd = rcvd->next;
  }

  // true
  return 1;
}

void updatercvd (int seqno, int flow_id)
{
  rcvd_t *rcvd;

  if ( NULL == (rcvd = (rcvd_t *)malloc(sizeof(rcvd_t))) ) {
    fprintf(stderr, "Memory Allocation Error.\n");
    exit(1);
  }

  rcvd->seqno = seqno;
  rcvd->flow_id = flow_id;
  rcvd->next = head.next;
  head.next = rcvd;
}

void freercvd (rcvd_t *rcvd)
{
  if (rcvd->next) freercvd(rcvd->next);
  free(rcvd);
  rcvd = NULL;
}

int main ( int argc, char **argv )
{
  FILE *fp_ns, *fp_et;
  int tx, rx, packet_size, flow_id, sequence, packet_id, 
      sum, node, cwnd;
  unsigned long int sum_all;
  char buffer[128], event, packet_type[8], flags[8], tx_address[16],
       rx_address[16], event_type[32], is_rto;
  double time, clock, granularity, first_recv_time, last_recv_time, throughput;
  double last_sent_time[MAXFLOW];

  // Init
  head.next = NULL;
  first_recv_time = 100000.0;
  last_recv_time  = -1.0;
  int i;
  for(i = 0; i < MAXFLOW; i++) last_sent_time[i] = -1.0;

  // Open Trace file (out.ns)
  if ( NULL == ( fp_ns = fopen ( argv[1], "r" ) ) ) {
    fprintf ( stderr, "Can't open %s\n", argv[1] );
    return 1;
  }

  // Open Event Trace file (out.et)
  if ( NULL == ( fp_et = fopen ( argv[2], "r" ) ) ) {
    fprintf ( stderr, "Can't open %s\n", argv[2] );
    return 1;
  }

  node = atoi ( argv[3] );
  granularity = atof ( argv[4] );

  // Goodput Calculation
  for ( sum = 0, sum_all = 0, clock = 0.0; feof ( fp_ns ) == 0; ) {
    /* 1行分のデータを解析 */
    fgets ( buffer, 128, fp_ns );
    sscanf ( buffer, "%c %lf %d %d %s %d %s %d %s %s %d %d",
     	 &event, &time, &tx, &rx, packet_type, &packet_size, flags, &flow_id,
	 tx_address, rx_address, &sequence, &packet_id );

    /* 該当するデータラインか確認する */
    // exception check
    if ( flow_id >= MAXFLOW ) {
	    printf("MAXFLOW ERROR! flow_id:%d\n", flow_id);
	    return 1;
    }

    // for counting retransmission timeout
    if ( event == '+' && rx == SW_NODE
	 && last_sent_time[flow_id] < time )
	    last_sent_time[flow_id] = time;

    // for calculating goodput
    if ( event != 'r' ) continue;
    if ( strcmp(packet_type, "tcp") != 0 ) continue;
    if ( rx != node )	continue;

    /* スループットの計算 Mbps*/
    if ( ( time - clock ) > granularity ) {
        throughput = ( (double) sum / granularity ) * 8.0 / 1000.0 / 1000.0;
	clock += granularity;
        printf ( "%f\t%f\t%d\n", clock, throughput, sum );
	sum = 0;
    }

    // is newdata? (uncount unnecessary restransmission)
    if ( isnew(sequence, flow_id) ){
      updatercvd(sequence, flow_id);
      if ( first_recv_time > time) first_recv_time = time;
      last_recv_time = time;
      sum     += packet_size;
      sum_all += (unsigned long int)packet_size;
    }
  } // for

  throughput = ( (double) sum_all / (last_recv_time - first_recv_time) ) 
                                                    * 8.0 / 1000.0 / 1000.0;

  // Count Retransmisson Timeout Event from Event Trace file
  for ( is_rto = 0; feof ( fp_et ) == 0; ) {
    /* 1行分のデータを解析 */
    fgets ( buffer, 128, fp_et );
    sscanf ( buffer, "%c %lf %d %d %s %s %d %d %d",
     	 &event, &time, &tx, &rx, packet_type, event_type, &flow_id,
	 &sequence, &cwnd );

    if ( time > last_sent_time[flow_id] ) continue;
    if ( strcmp(event_type, "TIMEOUT") == 0 ) is_rto = 1;
  }

  printf ( "%f\t%d\t%u\t%f\t%f\t%f\n",
	   throughput, is_rto, sum_all, last_recv_time - first_recv_time,
	   first_recv_time, last_recv_time);

  fclose ( fp_ns );
  fclose ( fp_et );

  freercvd( head.next );

  return 0;
}
