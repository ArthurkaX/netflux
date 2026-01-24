METHOD send : BOOL
VAR_INPUT
END_VAR
VAR
    nrResult: DINT; // Local result for SendTo
END_VAR

// === IMPLEMENTATION ===
tonSend(IN := NOT tonSend.Q, PT := tSendInterval);

IF tonSend.Q THEN
    bOwnSeq := bOwnSeq + 1;
    aSendBuf[0] := bOwnSeq;
    aSendBuf[1] := bLastRecvSeq;

    IF ptrSendData <> 0 AND uiSizeSendData > 0 THEN
         SysMemCpy(ADR(aSendBuf[2]), ptrSendData, uiSizeSendData);
    END_IF

    // SendTo: 7 args
	{warning disable C0196}
    SysSockSendTo(hSocket, ADR(aSendBuf), uiSizeSendData + 2, 0, ADR(saRemote), SIZEOF(saRemote), ADR(nrResult));
    
    // Update Stats
    udiTxCount := udiTxCount + 1;
    
    // Capture timestamp for statistics
    tLastTxTime := TIME();
    
    send := TRUE;
END_IF