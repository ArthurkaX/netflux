(*
    Method: CloseSocket
    Description: Properly closes the socket with shutdown to release port immediately
*)
METHOD PRIVATE CloseSocket
VAR
END_VAR

// === IMPLEMENTATION ===
// Shutdown socket first (releases port binding immediately)
IF hSocket <> 16#FFFFFFFF THEN
    // SOCKET_SD_BOTH = 2 (shutdown both send and receive)
    SysSockShutdown(hSocket, 2);
    
    // Now close the socket
    SysSockClose(hSocket);
    hSocket := 16#FFFFFFFF;
END_IF