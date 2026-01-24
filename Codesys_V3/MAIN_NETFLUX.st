PROGRAM MAIN_NETFLUX
VAR
    _fbTaskInfo: fbTaskInfo;

    // --- Unified Communication Block ---
    _fbNetflux_Socket: fbNetflux_Socket;
END_VAR

// === IMPLEMENTATION ===
(*
    Netflux Main Program.
    Uses the optimized fbNetflux_Socket to handle high-speed bidirectional UDP.
    Links the input/output GVL arrays to the network socket.
 *)

_fbTaskInfo();


// Call the socket block with parameters matching your network setup
_fbNetflux_Socket(
    xEnable := TRUE,

    // Connection Settings
    sRemoteIP := '192.168.88.156', // PC IP (Running Rust Sim)
    uiRemotePort := 2001, // Port Rust listens on
    uiLocalPort := 2000, // Port PLC listens on (2000 -> 2001)
    tSendInterval := T#1MS, // Send frequency (50Hz) - matches Rust tick rate

    // Data Buffers (Pointers to GVL arrays)
    ptrSendData    := ADR(GVL_IO.data_send),      // PLC sends data_send -> Rust
    uiSizeSendData := SIZEOF(GVL_IO.data_send),     
    
    ptrRecvData    := ADR(GVL_IO.data_recv),      // PLC receives data_recv <- Rust
    uiSizeRecvData := SIZEOF(GVL_IO.data_recv),      
    
    // Status Outputs
    xError => ,
    xConnected => ,
    uiPacketsReceivedPerCycle => ,
    tRoundTripTime => ,
    bLastPartnerSeq =>
);