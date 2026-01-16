(*
    Function Block: fbPUDP_Send
    Description: Manages the sending part of a UDP communication.
                 It periodically sends a packet containing a sequence number, a feedback
                 sequence number, and the data payload. It is designed to work in tandem
                 with the fbPUDP_Recieve block.
*)
FUNCTION_BLOCK fbNetflux_Send
VAR_INPUT
    // --- Connection Parameters ---
	i_uiRemotePort : UINT;      // The UDP port of the remote partner.
	i_sIPaddress : STRING[15];  // The IP address of the remote partner.
	i_tSendInterval : TIME := T#5MS; // The interval at which to send packets.
	
    // --- Link to Recieve Block ---
	i_hPeer: LWORD;              // The handle of the UDP peer, obtained from the fbPUDP_Recieve block.
	i_bPartnerSeqNumber : BYTE; // The last sequence number received from the partner, provided by fbPUDP_Recieve. This is sent back for feedback.
		
    // --- Data to Send ---
	i_ptrSendData : POINTER TO BYTE; // Pointer to the source buffer containing the data payload to send.
	i_uiSizeSendData : UINT;         // The size of the data payload to send.
END_VAR
VAR_OUTPUT
	o_bSequenceNumber : BYTE;   // The internal sequence number for outgoing packets. Increments with each send.
    o_bError: BOOL;        // Becomes TRUE if a library error occurs during sending.
    o_eErrorID: NBS.ERROR; // Propagates the specific error code from the underlying NBS library if an error occurs.
END_VAR
VAR
    // --- UDP library instances ---
	s_fbUDPSend : NBS.UDP_Send;
	s_tonSendPeriod : TON;      // Timer to trigger sending at the specified interval.
	s_IPaddress : NBS.IP_ADDR;  // Structure to hold the remote IP address.
	
    // --- Internal state ---
	s_xSend : BOOL;             // Trigger flag for sending, controlled by the timer.
	s_xInit : BOOL := TRUE;     // Flag for one-time initialization on the first scan.
	
	// --- Internal send buffer ---
    s_aSendBuffer: ARRAY[0..1460] OF BYTE; // Raw buffer used to construct the entire UDP packet before sending.
	s_ptrSendBuffer : POINTER TO BYTE := ADR(s_aSendBuffer);
	s_szTotalPacketSize : UINT; // Holds the total size of the packet to be sent (Header + Payload).
END_VAR

// === IMPLEMENTATION ===
(*
    This function block sends data via UDP.

    UDP Payload Structure created by this block:
    - Byte 0: s_bSequenceNumber (This block's own incrementing sequence number).
    - Byte 1: i_bPartnerSeqNumber (The sequence number received from the partner, used as feedback).
    - Byte 2...N: The actual data payload from i_ptrSendData.

    How it works:
    1. On the first scan, it initializes the remote IP address and calculates the total packet size. This is an optimization to avoid repeated calculations.
    2. A timer triggers the sending process at the interval specified by 'i_tSendInterval'.
    3. When triggered, it constructs the packet header in an internal buffer (s_aSendBuffer) and copies the user data payload.
    4. It increments its own sequence number for each packet.
    5. It calls the NBS.UDP_Send function block to transmit the constructed packet.
    6. It monitors for errors from the library and exposes them through the outputs.
*)

// 1. One-time initialization on the first scan.
IF s_xInit THEN
	// Set the remote IP address and calculate the total packet size.
    // This is done only once for efficiency.
	s_IPaddress.sAddr := i_sIPaddress;
    s_szTotalPacketSize := i_uiSizeSendData + 2; // Payload size + 2 bytes for the header.
	
	s_xInit := FALSE;
END_IF;

// 2. Generate a periodic trigger for sending. s_xSend will be TRUE for one cycle every i_tSendInterval.
s_tonSendPeriod(IN:= NOT s_xSend, PT:= i_tSendInterval, Q=> s_xSend);

// 3. When the timer triggers, prepare the packet.
IF s_xSend THEN
    // --- Construct the packet header ---
    o_bSequenceNumber := o_bSequenceNumber + 1; // Increment our own sequence number.
    s_aSendBuffer[0] := o_bSequenceNumber;      // Byte 0: Our sequence number.
    s_aSendBuffer[1] := i_bPartnerSeqNumber;    // Byte 1: The partner's sequence number (feedback).

    // --- Copy the data payload into the buffer after the header ---
    MEMUtils.MemCpy(pbyDest:= ADR(s_aSendBuffer[2]), 
                    pbySrc:= i_ptrSendData, 
                    dwSize:= i_uiSizeSendData);
END_IF;

// 4. Execute the UDP_Send instruction.
// It is called continuously, but the xExecute flag ensures it only acts when triggered.
s_fbUDPSend(
	xExecute:= s_xSend, 
	udiTimeOut:= 50000, // Timeout in microseconds (50ms)
	hPeer:= i_hPeer, 
	ipAddr:= s_IPaddress, 
	uiPort:= i_uiRemotePort, 
	szSize:= s_szTotalPacketSize, 
	pData:= s_ptrSendBuffer);

// 5. Handle error outputs from the library block.
o_bError := s_fbUDPSend.xError;
IF o_bError THEN
    o_eErrorID := s_fbUDPSend.eError;
END_IF;