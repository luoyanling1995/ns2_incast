/* -*-	Mode:C++; c-basic-offset:8; tab-width:8; indent-tabs-mode:t -*- */
/*
 * Copyright (c) 1997 Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. All advertising materials mentioning features or use of this software
 *    must display the following acknowledgement:
 *	This product includes software developed by the Daedalus Research
 *	Group at the University of California Berkeley.
 * 4. Neither the name of the University nor of the Laboratory may be used
 *    to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 * Contributed by the Daedalus Research Group, U.C.Berkeley
 * http://daedalus.cs.berkeley.edu
 *
 * @(#) $Header: 
 */

/*
 *   https://github.com/osada/sim-incast/
 */

#ifndef lint
static const char rcsid[] =
    "@(#) $Header: $";
#endif

#include "template.h"
#include "flags.h"
#include "tcp-sink.h"
#include "ip.h"
#include "hdr_qs.h"

#define TCP_TIMER_IA 100

class TcpIASink;

class IAAckTimer : public TimerHandler {
public:
	IAAckTimer(TcpIASink *a) : TimerHandler() { a_ = a; }
protected:
	virtual void expire(Event *e);
	TcpIASink *a_;
};

class TcpIASink : public DelAckSink {
public:
	TcpIASink(Acker*);
	virtual void recv(Packet* pkt, Handler* h);
	virtual void timeout(int tno);
        virtual void reset();

protected:
	virtual void add_to_ack(Packet* pkt);

	IAAckTimer ia_ack_timer_;
	double ia_ack_interval_;
	Packet* last_rcvd_pkt;
};

static class TcpIASinkClass : public TclClass {
public:
	TcpIASinkClass() : TclClass("Agent/TCPSink/IncastAvoidance") {}
	TclObject* create(int, const char*const*) {
		return (new TcpIASink(new Acker));
	}
} class_tcpiasink;

TcpIASink::TcpIASink(Acker* acker) : DelAckSink(acker), ia_ack_timer_(this),
				     last_rcvd_pkt(NULL)
{
	bind_time("ia_ack_interval_", &ia_ack_interval_);
	// bind("bytes_", &bytes_); // useby JOBS
}

/* Add fields to the ack. Not needed? */
void TcpIASink::add_to_ack(Packet* pkt) 
{
	// hdr_tcpasym *tha = hdr_tcpasym::access(pkt);
	// tha->ackcount() = delackcount_;
}

void TcpIASink::recv(Packet* pkt, Handler*) 
{
	int numToDeliver;
	int numBytes = hdr_cmn::access(pkt)->size();
	hdr_tcp *th = hdr_tcp::access(pkt);
	/* W.N. Check if packet is from previous incarnation */
	if (th->ts() < lastreset_) {
		// Remove packet and do nothing
		Packet::free(pkt);
		return;
	}
	acker_->update_ts(th->seqno(),th->ts(),ts_echo_rfc1323_);
	// next_ is also updated in update()
	numToDeliver = acker_->update(th->seqno(), numBytes);
	if (numToDeliver) {
                bytes_ += numToDeliver; // for JOBS
                recvBytes(numToDeliver);
        }

	// 2011.12.05 Shigeyuki Osada
	// for IncastAvoidance
        if (last_rcvd_pkt != NULL) {
                Packet::free(last_rcvd_pkt);
                last_rcvd_pkt = NULL;
        }
	last_rcvd_pkt = pkt->copy();
	ia_ack_timer_.resched(ia_ack_interval_);
	
        // If there's no timer and the packet is in sequence, set a timer.
        // Otherwise, send the ack and update the timer.
        if (delay_timer_.status() != TIMER_PENDING &&
                                th->seqno() == acker_->Seqno()) {
                // There's no timer, so we can set one and choose
		// to delay this ack.
		// If we're following RFC2581 (section 4.2) exactly,
		// we should only delay the ACK if we're know we're
		// not doing recovery, i.e. not gap-filling.
		// Since this is a change to previous ns behaviour,
		// it's controlled by an optional bound flag.
		// discussed April 2000 in the ns-users list archives.
		if (RFC2581_immediate_ack_ && 
			(th->seqno() < acker_->Maxseen())) {
			// don't delay the ACK since
			// we're filling in a gap
		} else if (SYN_immediate_ack_ && (th->seqno() == 0)) {
			// don't delay the ACK since
			// we should respond to the connection-setup
			// SYN immediately
		} else {
			// delay the ACK and start the timer.
	                save_ = pkt;
        	        delay_timer_.resched(interval_);
                	return;
		}
        }
        // If there was a timer, turn it off.
	if (delay_timer_.status() == TIMER_PENDING) 
		delay_timer_.cancel();
	ack(pkt);
        if (save_ != NULL) {
                Packet::free(save_);
                save_ = NULL;
        }

	Packet::free(pkt);
}


void TcpIASink::timeout(int tno)
{
	Packet* pkt = 0;
	switch (tno) {
	case 0:
	case TCP_TIMER_DELACK:
		/*
		 * The timer expired so we ACK the last packet seen.
		 * tno == 0 always means DelAckTimeout
		 * since superclass is written so.
		 */
		pkt = save_;
		ack(pkt);
		save_ = 0;
		Packet::free(pkt);
		break;
	case TCP_TIMER_IA:
		/*
		 * 2011.12.05 Shigeyuki Osada
		 * for IncastAvoidance additional duplicated Ack
		 */
		pkt = last_rcvd_pkt;
		ack(pkt);
		ack(pkt);
		ack(pkt);
		last_rcvd_pkt = 0;
		Packet::free(pkt);
		break;
	default:
		break;
	}
}

void TcpIASink::reset()
{
    if (delay_timer_.status() == TIMER_PENDING)
        delay_timer_.cancel();
    if (ia_ack_timer_.status() == TIMER_PENDING)
	ia_ack_timer_.cancel();
    TcpSink::reset();
}

void IAAckTimer::expire(Event* /*e*/) {
	a_->timeout(TCP_TIMER_IA);
}
