(*
    Function Block: fbNetflux_Socket (v5 - Final Mixed Signatures)
    Description: Unified UDP Sender/Receiver using SysSocket logic.
                 Signatures Tuned:
                 - RecvFrom/SendTo/InetAddr: REQUIRE pResult.
                 - Bind/Ioctl: NO pResult (3 args).
 *)
FUNCTION_BLOCK fbNetflux_Socket
VAR_INPUT
    xEnable: BOOL := TRUE;
    xReconnect: BOOL := FALSE;  // Rising edge triggers reconnection

    // --- Network Config ---
    sRemoteIP: STRING(15);
    uiRemotePort: UINT;
    uiLocalPort: UINT;
    tSendInterval: TIME := T#2MS;

    // --- Data Handlers ---
    ptrSendData: POINTER TO BYTE;
    uiSizeSendData: UDINT;

    ptrRecvData: POINTER TO BYTE;
    uiSizeRecvData: UDINT;
END_VAR
VAR_OUTPUT
    xError: BOOL;
    xConnected: BOOL;

    uiPacketsReceivedPerCycle: UINT;
    tRoundTripTime: TIME;
    bLastPartnerSeq: BYTE;
    
    // Statistics
    udiTxCount: UDINT;
    udiRxCount: UDINT;
    
    // Statistics - Optional (calculated when Statistics() is called)
    tPartnerTxPeriod: TIME;      // Partner's transmission period
    tOwnRealTxPeriod: TIME;      // Own real transmission period
    tInstantRTT: TIME;           // Instantaneous RTT
    uiInstantRxSkipped: UINT;    // Instantaneous RX skipped packets
    
    // Diagnostics
    eCurrentState: ENUM_NetfluxSocketState;  // Current state for debugging
END_VAR
VAR
    hSocket: UDINT := 16#FFFFFFFF;

    saLocal: SOCKADDRESS;
    saRemote: SOCKADDRESS;

    eState: ENUM_NetfluxSocketState := ENUM_NetfluxSocketState.IDLE;
    
    xFirstCycle: BOOL := TRUE;  // Flag to detect cold start / program reload
    udiInitCounter: UDINT := 0;  // Counter for reliable cold start detection

    tonSend: TON;
    tonWatchdog: TON := (PT := T#1s);

    aRecvBuf: ARRAY[0..1500] OF BYTE;
    aSendBuf: ARRAY[0..1500] OF BYTE;

    bOwnSeq: BYTE;
    bLastRecvSeq: BYTE;

    // --- Helpers ---
    diRes: DINT;
    diRecvBytes: DINT;
    diSentBytes: DINT;
    diDummy: DINT;
    xi: DINT;

    xNewData: BOOL;

    nrResult: DINT;
    
    // --- Statistics Internal Variables ---
    tLastRxTime: TIME;           // Timestamp of last received packet
    tLastTxTime: TIME;           // Timestamp of last sent packet
    bPrevRecvSeq: BYTE;          // Previous received sequence number
    bPrevOwnSeq: BYTE;           // Previous own sequence number
    xFirstRx: BOOL := TRUE;      // Flag for first reception
    xFirstTx: BOOL := TRUE;      // Flag for first transmission
    
    // --- Reconnect Edge Detection ---
    xReconnect_prev: BOOL := FALSE;  // Previous state of xReconnect
    
    // --- Error Recovery ---
    tonErrorRecovery: TON := (PT := T#5s);  // Auto-recovery timer for ERROR state
END_VAR

// === IMPLEMENTATION ===
// Cold Start Detection: Force reset on program reload
// Use both flag and counter for reliability (CODESYS may not reset BOOL := TRUE on download)
IF xFirstCycle OR udiInitCounter = 0 THEN
    xFirstCycle := FALSE;
    udiInitCounter := 1;
    
    // Check if socket handle exists and might be stale
    IF hSocket <> 16#FFFFFFFF THEN
        xi := 0;
        diDummy := SIZEOF(xi);
		{warning disable C0196}
        diRes := SysSockGetOption(hSocket, SOCKET_SOL, SOCKET_SO_TYPE, ADR(xi), ADR(diDummy));
        
        // If GetOption fails, socket is invalid/stale
        IF diRes <> 0 THEN
            // Socket is stale, just reset handle
            hSocket := 16#FFFFFFFF;
        ELSE
            // Socket seems valid but we're restarting - close it properly
            THIS^.CloseSocket();
        END_IF
    END_IF
    
    // Force clean restart
    eState := ENUM_NetfluxSocketState.IDLE;
    xError := FALSE;
    xConnected := FALSE;
END_IF

// Manual Reconnect Trigger: Detect rising edge on xReconnect
IF xReconnect AND NOT xReconnect_prev THEN
    // Close existing socket
    THIS^.CloseSocket();
    
    // Reset to IDLE to trigger reconnection
    eState := ENUM_NetfluxSocketState.IDLE;
    xError := FALSE;
    xConnected := FALSE;
END_IF
xReconnect_prev := xReconnect;

CASE eState OF
    ENUM_NetfluxSocketState.IDLE: // Idle / Init
        IF xEnable THEN
            eState := ENUM_NetfluxSocketState.CREATE;
        END_IF

    ENUM_NetfluxSocketState.CREATE: // Create Socket
        hSocket := SysSockCreate(SOCKET_AF_INET, SOCKET_DGRAM, SOCKET_IPPROTO_UDP, ADR(nrResult));

        IF hSocket <> 16#FFFFFFFF THEN
            // Set SO_REUSEADDR to allow port reuse (critical for reconnection!)
            // This allows binding to a port in TIME_WAIT state
            xi := 1;
            diRes := SysSockSetOption(hSocket, SOCKET_SOL, SOCKET_SO_REUSEADDR, ADR(xi), SIZEOF(xi));
            
            // Try to set SO_REUSEPORT as well (may not be available on all systems)
            // This allows multiple sockets to bind to the same port
            // Ignore errors as this is optional
            IF diRes = 0 THEN
                xi := 1;
                diDummy := SysSockSetOption(hSocket, SOCKET_SOL, 15 (*SO_REUSEPORT*), ADR(xi), SIZEOF(xi));
                // Continue even if SO_REUSEPORT fails
            END_IF
            
            IF diRes = 0 THEN
                eState := ENUM_NetfluxSocketState.BIND;
            ELSE
                // Failed to set socket option, close and error
                THIS^.CloseSocket();
                eState := ENUM_NetfluxSocketState.ERROR;
            END_IF
        ELSE
            eState := ENUM_NetfluxSocketState.ERROR;
        END_IF

    ENUM_NetfluxSocketState.BIND: // Bind TO:
        saLocal.sin_family := SOCKET_AF_INET;
        saLocal.sin_port := SysSockHtons(uiLocalPort);
        saLocal.sin_addr.ulAddr := SOCKET_INADDR_ANY;

        // SysSockBind: 3 args (Handle, pAddr, iSize) - NO pResult
        diRes := SysSockBind(hSocket, ADR(saLocal), SIZEOF(saLocal));

        IF diRes = 0 THEN
            eState := ENUM_NetfluxSocketState.NONBLOCK;
        ELSE
            eState := ENUM_NetfluxSocketState.ERROR;
        END_IF

    ENUM_NetfluxSocketState.NONBLOCK: // Non-Blocking
        xi := 1;
        // SysSockIoctl: 3 args (Handle, Cmd, pArg) - NO pResult
        diRes := SysSockIoctl(hSocket, SOCKET_FIONBIO, ADR(xi));

        IF diRes = 0 THEN
            eState := ENUM_NetfluxSocketState.RUNNING;

            saRemote.sin_family := SOCKET_AF_INET;
            saRemote.sin_port := SysSockHtons(uiRemotePort);
            // InetAddr: 2 args (String, pResult) - WITH pResult
            saRemote.sin_addr.ulAddr := SysSockInetAddr(sRemoteIP, ADR(nrResult));
        ELSE
            eState := ENUM_NetfluxSocketState.ERROR;
        END_IF

    ENUM_NetfluxSocketState.RUNNING: // RUNNING
        xConnected := NOT tonWatchdog.Q;
        IF NOT xEnable THEN
            THIS^.CloseSocket();
            eState := ENUM_NetfluxSocketState.IDLE;
            RETURN;
        END_IF

        // RECV LOOP
        uiPacketsReceivedPerCycle := 0;

        FOR xi := 0 TO 20 DO
            // RecvFrom: 7 args (Handle, Buf, Size, Flags, Addr, Size, pResult)
            diRecvBytes := SysSockRecvFrom(hSocket, ADR(aRecvBuf), SIZEOF(aRecvBuf), 0, ADR(saRemote), SIZEOF(saRemote), ADR(nrResult));

            IF diRecvBytes > 0 THEN
                uiPacketsReceivedPerCycle := uiPacketsReceivedPerCycle + 1;
                udiRxCount := udiRxCount + 1; // Update Stats

                IF diRecvBytes >= 2 THEN
                    bLastRecvSeq := aRecvBuf[0];
                    bLastPartnerSeq := bLastRecvSeq;
                    
                    // Capture timestamp for statistics
                    tLastRxTime := TIME();

                    tonWatchdog(IN := FALSE);

                    IF ptrRecvData <> 0 AND uiSizeRecvData > 0 THEN
                         IF UDINT_TO_INT(uiSizeRecvData) <= (diRecvBytes - 2) THEN
                            SysMemCpy(ptrRecvData, ADR(aRecvBuf[2]), uiSizeRecvData);
                         END_IF
                    END_IF
                END_IF
            ELSE
                EXIT;
            END_IF
        END_FOR

        tonWatchdog(IN := TRUE);
        

        
      

    ENUM_NetfluxSocketState.ERROR: // Error
        xError := TRUE;
        
        // Auto-recovery: Try to reconnect after timeout if still enabled
        tonErrorRecovery(IN := xEnable);
        
        IF tonErrorRecovery.Q THEN
            // Close socket if it exists
            THIS^.CloseSocket();
            
            // Reset to IDLE to retry connection
            eState := ENUM_NetfluxSocketState.IDLE;
            xError := FALSE;
            tonErrorRecovery(IN := FALSE);  // Reset timer
        END_IF
        
        // If disabled, reset error state
        IF NOT xEnable THEN
            tonErrorRecovery(IN := FALSE);
            eState := ENUM_NetfluxSocketState.IDLE;
            xError := FALSE;
        END_IF

END_CASE

// Update diagnostic output
eCurrentState := eState;