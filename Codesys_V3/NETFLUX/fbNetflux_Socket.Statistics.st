METHOD Statistics: BOOL
VAR_INPUT
END_VAR
VAR
    tCurrentTime: TIME;
    tRxDelta: TIME;
    tTxDelta: TIME;
    iSeqDelta: INT;
END_VAR

// === IMPLEMENTATION ===
// This method calculates derived statistics based on timing and sequence information.
// It is optional and only calculates when called.

tCurrentTime := TIME();

// ========================================
// 1. Partner's Transmission Period
// ========================================
// Calculate time between received packets
IF NOT xFirstRx THEN
    tRxDelta := tCurrentTime - tLastRxTime;

    // Only update if we received a new packet (tRxDelta is reasonable)
    IF tRxDelta > T#0ms AND tRxDelta < T#10s THEN
        tPartnerTxPeriod := tRxDelta;
    END_IF
ELSE
    // First reception - no delta yet
    IF tLastRxTime > T#0ms THEN
        xFirstRx := FALSE;
    END_IF
END_IF

// ========================================
// 2. Own Real Transmission Period
// ========================================
// Calculate actual time between sent packets
IF NOT xFirstTx THEN
    tTxDelta := tCurrentTime - tLastTxTime;

    // Only update if we sent a new packet (tTxDelta is reasonable)
    IF tTxDelta > T#0ms AND tTxDelta < T#10s THEN
        tOwnRealTxPeriod := tTxDelta;
    END_IF
ELSE
    // First transmission - no delta yet
    IF tLastTxTime > T#0ms THEN
        xFirstTx := FALSE;
    END_IF
END_IF

// ========================================
// 3. Instantaneous RTT
// ========================================
// RTT is calculated based on the feedback sequence number
// The partner echoes our sequence in their packet (aSendBuf[1] = bLastRecvSeq)
// When we receive a packet, aRecvBuf[1] contains our sequence that partner echoed back
// RTT = time since we sent that sequence number

// For simplicity, we estimate RTT as half of the partner's transmission period
// This assumes symmetric delay and regular transmission
IF tPartnerTxPeriod > T#0ms THEN
    // Simple estimation: RTT ≈ Partner period / 2
    // More accurate would require tracking send times per sequence number
    tInstantRTT := tPartnerTxPeriod / 2;
END_IF

// Alternative RTT calculation based on sequence delta:
// If partner responds immediately, RTT ≈ our TX period
IF tOwnRealTxPeriod > T#0ms AND bLastRecvSeq <> 0 THEN
    // Use own period as RTT estimate if partner is responsive
    tInstantRTT := tOwnRealTxPeriod;
END_IF

// ========================================
// 4. Instantaneous RX Skipped Packets
// ========================================
// Calculate how many packets were skipped based on sequence number delta
IF bPrevRecvSeq <> 0 THEN
    // Calculate sequence delta (handle byte wraparound)
    iSeqDelta := BYTE_TO_INT(bLastRecvSeq) - BYTE_TO_INT(bPrevRecvSeq);

    // Handle wraparound: if delta is negative, add 256
    IF iSeqDelta < 0 THEN
        iSeqDelta := iSeqDelta + 256;
    END_IF

    // Skipped packets = delta - 1 (delta of 1 means consecutive, no skip)
    IF iSeqDelta > 1 THEN
        uiInstantRxSkipped := INT_TO_UINT(iSeqDelta - 1);
    ELSE
        uiInstantRxSkipped := 0;
    END_IF
ELSE
    uiInstantRxSkipped := 0;
END_IF

// Update previous sequence for next calculation
bPrevRecvSeq := bLastRecvSeq;

Statistics := TRUE;