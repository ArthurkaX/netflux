PROGRAM MAIN_NETFLUX
VAR
	_fbTaskInfo : fbTaskInfo;	

	// --- Instances of the netflux function blocks ---
	_fbNetflux_Recieve : fbNetflux_Recieve; // Instance of the block responsible for receiving UDP data.
	_fbNetflux_Send : fbNetflux_Send := (i_tSendInterval := TIME#4ms);       // Instance of the block responsible for sending UDP data.
	
	_fbNetflux_Statistics : fbNetflux_Statistics;
	
	_xTuneSend : BOOL;
END_VAR

// === IMPLEMENTATION ===
(*
    This is the main program that demonstrates the usage of the PUDP (Pseudo-UDP) blocks.
    It establishes a bidirectional communication link where one block handles receiving
    and the other handles sending, using a shared UDP socket.
*)

_fbTaskInfo();

// --- Call the Recieve block ---
// This block opens the UDP port and continuously listens for incoming packets.
_fbNetflux_Recieve(
	i_uiLocalPort:= 2000,                               // Listen on UDP port 2000.
	i_ptrReceiveData:= ADR(GVL.data_recv),              // Pointer to the global variable structure where received data will be stored.
	i_uiSizeReceiveData:= SIZEOF(GVL.data_recv),        // The size of the destination data structure.
	i_tWatchInterval:= T#30MS,                            // Set a 1-second watchdog timer. If no new packet arrives, an error is flagged.
	i_xKeepValuesOnTimeout:= FALSE);                    // If the watchdog times out, clear the destination data structure for safety.
	

//GVL.data_send := GVL.data_recv;




// IF _xTuneSend THEN
// 	_fbPUDP_Send.i_tSendInterval := _fbPUDP_Statistics.o_tAvgPartnerInterval;
// END_IF	
// --- Call the Send block ---
// This block periodically sends data to the remote partner.
_fbNetflux_Send(
	i_uiRemotePort:= 2001,                              // Send data to UDP port 2000 on the remote device.
	i_sIPaddress:= '172.10.10.10',                     // The IP address of the remote device.
	i_ptrSendData:= ADR(GVL.data_send),                 // Pointer to the global variable structure containing the data to be sent.
	i_uiSizeSendData:= SIZEOF(GVL.data_send),           // The size of the data structure to be sent.
	
	// --- Linking the Send block to the Recieve block ---
	i_hPeer:= _fbNetflux_Recieve.o_hPeer,                   // Use the same UDP socket handle that was opened by the Recieve block. This is crucial.
	i_bPartnerSeqNumber:= _fbNetflux_Recieve.o_bPartnerSeqNumber // Provide the sequence number from the last received packet as feedback.
);

_fbNetflux_Statistics(
	i_rTaskCycle := _fbTaskInfo.rTaskCycle,
	i_bRecvSeqNumber:= _fbNetflux_Recieve.o_bPartnerSeqNumber, 
	i_bSequenceNumber:= _fbNetflux_Send.o_bSequenceNumber, 
	i_bFeedBackSeqNumber:= _fbNetflux_Recieve.o_bCurrentFeedbackSeqNumber);