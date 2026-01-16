(*
    Function Block: fbPUDP_Recieve
    Description: Manages the receiving part of a UDP communication.
                 It uses a sequence number to discard duplicate or out-of-order packets
                 and a watchdog timer to detect communication loss. It provides outputs
                 needed by a corresponding Send block.
*)
FUNCTION_BLOCK fbNetflux_Recieve
VAR_INPUT
    // --- Connection Parameters ---
    i_uiLocalPort : UINT;   // Local UDP port to listen on.

    // --- Data Reception Parameters ---
	i_ptrReceiveData : POINTER TO BYTE; // Pointer to the destination buffer where the received data payload will be stored.
	i_uiSizeReceiveData : UINT;         // The exact size of the data payload to copy. The user is responsible for ensuring this size matches the sender's payload.

    // --- Watchdog Parameters ---
    i_tWatchInterval : TIME := T#1S;    // Watchdog timeout. If no new valid packet arrives within this interval, o_bError is set.
    i_xKeepValuesOnTimeout : BOOL;      // If TRUE, the last received values are kept in the destination buffer on watchdog timeout. If FALSE, the buffer is cleared for safety.
END_VAR
VAR_OUTPUT
    o_xError: BOOL;        // Becomes TRUE if no valid packet has been received, if the watchdog has timed out, or if a library error occurs.
    o_eErrorID: NBS.ERROR; // Propagates the specific error code from the underlying NBS library if an error occurs.
	o_hPeer: LWORD;         // Outputs the handle of the UDP peer. This is required by the corresponding Send block to use the same socket.
	o_bPartnerSeqNumber : BYTE; // Outputs the last received sequence number from the partner. This is needed by the Send block to send it back as a feedback sequence number.
	o_bCurrentFeedbackSeqNumber : BYTE; // Stores the feedback sequence number from the current valid packet. Used by the watchdog.
END_VAR
VAR
	// --- Internal state flags ---
	s_xFirstPacketReceived : BOOL;      // Flag to track if at least one valid packet has been received since startup or last timeout.
    s_xWatchdogTimeout : BOOL;          // Flag set by the watchdog timer when no new packet arrives in time.

    // --- UDP library instances ---
    s_fbPeer: NBS.UDP_Peer := (xEnable := TRUE); // Manages the UDP socket itself.
	s_fbUDPReceive : NBS.UDP_Receive;            // Handles the continuous reception of data into the internal buffer.
    s_tonWatchdog : TON;                         // Watchdog timer to detect communication loss.
 
    // --- Internal receive buffer ---
    s_aRecvBuffer: ARRAY[0..1460] OF BYTE;       // Raw buffer that receives the entire UDP packet.
	s_ptrRecvBuffer : POINTER TO BYTE := ADR(s_aRecvBuffer);
	s_szRecvBuffer : UINT := SIZEOF(s_aRecvBuffer);
	
	// --- Sequence number handling ---
	s_bPreviousRecvSeqNumber : BYTE;    // Stores the sequence number of the last processed packet to detect new ones.
	
    s_bPreviousFeedbackSeqNumber : BYTE;// Stores the feedback sequence number from the previous cycle to detect changes.
END_VAR
VAR_TEMP
    xIsNewPacket : BOOL;                // Temporary flag to indicate if a received packet is newer than the last processed one.
END_VAR

// === IMPLEMENTATION ===
(*
    This function block receives data via UDP and writes it into a specified destination buffer.

    Expected UDP Payload Structure:
    - Byte 0: Sequence Number (rolls over from 255 to 0). Used to identify new/unique packets.
    - Byte 1: Feedback Sequence Number. A copy of the sender's own receive sequence number. Used here for the watchdog.
    - Byte 2...N: The actual data payload.

    How it works:
    1. It continuously listens for incoming UDP packets on the specified port using the NBS library blocks.
    2. It checks for a new packet by comparing the sequence number (Byte 0) of the incoming packet with the last one processed.
    3. A robust sequence number validation handles counter wrap-around and rejects old, duplicate, or out-of-order packets.
    4. For valid new packets, a fixed-size data payload (defined by 'i_uiSizeReceiveData') is copied from the internal buffer to the user-provided destination buffer.
    5. A watchdog timer monitors the reception of valid packets. If no new packet arrives within 'i_tWatchInterval', an error is flagged.
    6. If the watchdog expires, the behavior is controlled by 'i_bKeepValuesOnTimeout' (either clear the destination buffer or keep the last valid data).
*)

// 1. Initialize and open the UDP Peer on the specified local port.
s_fbPeer(uiPort:=i_uiLocalPort);
// 1a. Output the peer handle so a corresponding Send block can use the same socket.
o_hPeer := s_fbPeer.hPeer;

// 2. Execute the UDP_Receive instruction to listen for data. This block continuously updates s_aRecvBuffer with the latest received packet.
s_fbUDPReceive(
	xEnable:= s_fbPeer.xActive, 
	hPeer:= s_fbPeer.hPeer, 
	szSize:= s_szRecvBuffer, 
	pData:= s_ptrRecvBuffer);
	
// 3. Check for a new packet by detecting a change in the sequence number byte.
IF s_aRecvBuffer[0] <> s_bPreviousRecvSeqNumber THEN
	// 3a. Pass the received sequence number to the output immediately. The Send block will use this for feedback.
	o_bPartnerSeqNumber := s_aRecvBuffer[0];
	
    // A packet with a different sequence number has arrived.
    // Now, validate if it's logically NEWER than the last one, handling the 8-bit counter wrap-around.
    // This prevents processing old packets that may arrive out of order.
    // A packet is considered "new" if it's the first one, its number is slightly ahead, or it has wrapped around.
    xIsNewPacket := NOT s_xFirstPacketReceived OR
        (s_aRecvBuffer[0] > s_bPreviousRecvSeqNumber AND s_aRecvBuffer[0] - s_bPreviousRecvSeqNumber < 128) OR
        (s_aRecvBuffer[0] < s_bPreviousRecvSeqNumber AND s_bPreviousRecvSeqNumber - s_bPreviousRecvSeqNumber > 128);

	IF xIsNewPacket THEN
        // --- Process Valid New Packet ---
        s_xFirstPacketReceived := TRUE;
        o_bCurrentFeedbackSeqNumber := s_aRecvBuffer[1]; // Store feedback number for the watchdog.

        // Copy the data payload (starting from the 3rd byte) from the internal buffer to the destination buffer.
        MEMUtils.MemCpy(pbyDest:= i_ptrReceiveData, 
                        pbySrc:= ADR(s_aRecvBuffer[2]), 
                        dwSize:= i_uiSizeReceiveData);

        // IMPORTANT: Update the previous sequence number *only after* successfully processing a valid new packet.
        s_bPreviousRecvSeqNumber := s_aRecvBuffer[0];
	END_IF;
END_IF;

// 4. Watchdog timer logic. The timer is active if a valid packet has been received but no new one has arrived.
// It checks if the feedback sequence number has changed. A change indicates the partner has received our data, implying the connection is alive.
s_tonWatchdog(
    IN:= (o_bCurrentFeedbackSeqNumber = s_bPreviousFeedbackSeqNumber) AND s_xFirstPacketReceived, 
    PT:= i_tWatchInterval, 
    Q=> s_xWatchdogTimeout);

// Update the previous feedback number for the next cycle's comparison.
s_bPreviousFeedbackSeqNumber := o_bCurrentFeedbackSeqNumber;

// 5. Handle watchdog timeout.
IF s_xWatchdogTimeout AND NOT i_xKeepValuesOnTimeout THEN
    // If the timeout occurs and we are not keeping values, clear the destination buffer for safety.
    MEMUtils.MemSet(pbyBuffer:= i_ptrReceiveData, 
                    byValue:= 0, 
                    dwSize:= i_uiSizeReceiveData);
	
    // Reset the state to require a new "first" packet.
    s_xFirstPacketReceived := FALSE;
END_IF;

// 6. Aggregate final error output. An error exists if we haven't received a valid packet yet, the watchdog timed out, or a library block has an error.
o_xError := NOT s_xFirstPacketReceived OR s_xWatchdogTimeout OR s_fbPeer.xError OR s_fbUDPReceive.xError;

// 7. Propagate specific error codes from the underlying library for easier debugging.
IF s_fbPeer.xError THEN
    o_eErrorID := s_fbPeer.eError;
ELSIF s_fbUDPReceive.xError THEN
    o_eErrorID := s_fbUDPReceive.eError;
END_IF;