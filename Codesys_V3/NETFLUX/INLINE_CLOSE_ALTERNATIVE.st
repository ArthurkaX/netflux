(*
    Alternative version without CloseSocket method
    Use this if method calls are not working
*)

// Replace THIS^.CloseSocket() with this inline code:

// Inline socket close
IF hSocket <> 16#FFFFFFFF THEN
    SysSockShutdown(hSocket, 2);  // SOCKET_SD_BOTH = 2
    SysSockClose(hSocket);
    hSocket := 16#FFFFFFFF;
END_IF
