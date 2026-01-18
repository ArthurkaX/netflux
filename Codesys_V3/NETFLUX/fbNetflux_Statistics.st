(*
    Function Block: fbPUDP_Statistics_V2
    Description: Calculates communication statistics with alternative logic.
                 - Intervals are measured by timing the duration of a full sequence number cycle (0-255).
                 - RTT is measured by tracking a single sequence number until its acknowledgment is received.
                 - Packet loss is calculated by detecting gaps in sequence numbers.
*)
FUNCTION_BLOCK fbNetflux_Statistics
VAR_INPUT
	i_xStatReset : BOOL; // Resets all statistical data.
	i_bRecvSeqNumber : BYTE; // The sequence number from the partner's last received packet.
	i_bSequenceNumber : BYTE;   // Your own send sequence number from the Send block.
	i_bFeedbackSeqNumber : BYTE; // The feedback from the partner (your own sequence number being returned).
    i_rTaskCycle : REAL; // Standard precision cycle time in ms
END_VAR
VAR_OUTPUT
    // --- Interval Statistics (calculated over a full ~256-packet cycle) ---
    o_rAvgPartnerInterval : REAL;       // Average time between packets received from the partner.
    o_rAvgOwnInterval : REAL;           // Average time between packets sent by this PLC.

    // --- Round Trip Time (RTT) Statistics ---
    o_rLastRTT : REAL;                  // The last measured round trip time.

    // --- Packet Loss Statistics ---
    o_bTotalPartnerLostPackets : BYTE;     // Total packets lost from the partner (gaps in i_bPartnerSeqNumber).
    o_bTotalFeedbackLostPackets : BYTE;     // Total acknowledgments lost from the partner (gaps in i_bCurrentFeedbackSeqNumber).
END_VAR
VAR
    // --- Triggers ---
    s_trigReset : R_TRIG;
    s_trigNewRecvPacket : R_TRIG;
    s_trigNewSendPacket : R_TRIG;
    s_trigFeedbackSeqNumber : R_TRIG;
	s_trigSendPacketRound : R_TRIG;
	s_trigRecvPacketRound : R_TRIG;
	s_trigFeedbackPacketRound : R_TRIG;
	

    // --- Own Send Interval Internals ---
    s_rOwnCycleCounter : REAL;
    s_bPrevSendSeqNumber : BYTE;
    s_xOwnCycleTiming : BOOL;

    // --- Partner Interval Internals ---
    s_rPartnerCycleCounter : REAL;
    s_bPrevRecvSeqNumber : BYTE;

    // --- Packet Loss Feedback Internals ---
    s_bPrevFeedBackSeqNumber : BYTE;
    s_xFirstPartnerPacket : BOOL := TRUE;
    s_xFirstAckPacket : BOOL := TRUE;

	// --- RTT Internals ---
    s_rRTTCounter : REAL;
    s_bRTT_TrackedSeqNum : BYTE;
END_VAR
VAR_TEMP
    uiLostCount : UINT;
END_VAR

// === IMPLEMENTATION ===
//Triggers
s_trigReset(CLK:= i_xStatReset);
s_trigNewRecvPacket(CLK:= i_bRecvSeqNumber <> s_bPrevRecvSeqNumber);
s_trigNewSendPacket(CLK:= i_bSequenceNumber <> s_bPrevSendSeqNumber);
s_trigFeedbackSeqNumber(CLK:= i_bFeedBackSeqNumber <> s_bPrevFeedBackSeqNumber);
s_trigSendPacketRound(CLK:= i_bSequenceNumber >= 0 AND i_bSequenceNumber < 3);
s_trigRecvPacketRound(CLK:= i_bRecvSeqNumber >= 0 AND i_bRecvSeqNumber < 5);
s_trigFeedbackPacketRound(CLK:= i_bFeedbackSeqNumber >= 0 AND i_bFeedbackSeqNumber < 15);

//Average time between packets received from the partner
IF s_trigSendPacketRound.Q THEN
	o_rAvgOwnInterval := (s_rOwnCycleCounter + i_rTaskCycle) / 256.0;
	s_rOwnCycleCounter := 0.0;
ELSE
	s_rOwnCycleCounter := s_rOwnCycleCounter + i_rTaskCycle;
END_IF
//Average time between packets sent by this PLC.
IF s_trigRecvPacketRound.Q THEN
	o_rAvgPartnerInterval := (s_rPartnerCycleCounter + i_rTaskCycle) / 256.0;
	s_rPartnerCycleCounter := 0.0;
ELSE
	s_rPartnerCycleCounter := s_rPartnerCycleCounter + i_rTaskCycle;
END_IF

// Total packets lost from the feedback (gaps in i_bFeedBackSeqNumber).
IF i_bFeedBackSeqNumber - s_bPrevFeedBackSeqNumber > 1 THEN
	o_bTotalFeedbackLostPackets := o_bTotalFeedbackLostPackets + (i_bFeedBackSeqNumber - s_bPrevFeedBackSeqNumber - 1);
END_IF

IF s_trigFeedbackPacketRound.Q THEN
	o_bTotalFeedbackLostPackets := 0;
END_IF

// Total packets lost from the partner
IF i_bRecvSeqNumber - s_bPrevRecvSeqNumber > 1 THEN
	o_bTotalPartnerLostPackets := o_bTotalPartnerLostPackets + (i_bRecvSeqNumber - s_bPrevRecvSeqNumber - 1);
END_IF

IF s_trigRecvPacketRound.Q THEN
	o_bTotalPartnerLostPackets := 0;
END_IF

// The last measured round trip time.
IF s_trigNewSendPacket.Q AND s_bRTT_TrackedSeqNum = 0 THEN
	s_bRTT_TrackedSeqNum := i_bSequenceNumber;
	s_rRTTCounter := 0.0;
ELSE
	s_rRTTCounter := s_rRTTCounter + i_rTaskCycle;
END_IF

IF s_bRTT_TrackedSeqNum = i_bFeedbackSeqNumber THEN
	o_rLastRTT := s_rRTTCounter;
	s_bRTT_TrackedSeqNum := 0;
END_IF

//Auxilary save previous values
s_bPrevRecvSeqNumber := i_bRecvSeqNumber;
s_bPrevSendSeqNumber := i_bSequenceNumber;
s_bPrevFeedBackSeqNumber := i_bFeedBackSeqNumber;