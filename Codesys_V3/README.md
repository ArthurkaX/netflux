# Netflux for CODESYS V3

This directory contains the original CODESYS V3 implementation of the Netflux protocol.

## Contents
* `MAIN_NETFLUX.st`: Main program example.
* `NETFLUX/`: Library folder containing all Function Blocks and DUTs.
  * `fbNetflux_Recieve`: Handles UDP reception and watchdog.
  * `fbNetflux_Send`: Handles UDP transmission and sequence numbering.
  * `fbNetflux_Statistics`: Calculates packet loss, round trip time, and jitter.

## Implementation & Usage

The basic implementation requires instantiating the `Recieve` and `Send` blocks. The `Recieve` block opens the port, and its handle (`o_hPeer`) is passed to the `Send` block.

**Execution Order is Critical for minimum latency:**

1. Call `_fbNetflux_Recieve` to process any incoming packet.
2. Execute your main application logic (use received data, prepare data to send).
3. Call `_fbNetflux_Send` to transmit your data.

```ST
// MAIN_netflux.st

// 1. Call the Recieve block first
_fbNetflux_Recieve(
    i_uiLocalPort:= 2000,
    i_ptrReceiveData:= ADR(GVL.data_recv),
    i_uiSizeReceiveData:= SIZEOF(GVL.data_recv),
    i_tWatchInterval:= T#4MS
);

// 2. Your application logic goes here
GVL.data_send := GVL.data_recv; // Example: mirror received data

// 3. Call the Send block last
_fbNetflux_Send(
    i_uiRemotePort:= 2000,
    i_sIPaddress:= '192.168.88.211',
    i_ptrSendData:= ADR(GVL.data_send),
    i_uiSizeSendData:= SIZEOF(GVL.data_send),
    i_hPeer:= _fbNetflux_Recieve.o_hPeer, // Link to the Recieve block's socket
    i_bPartnerSeqNumber:= _fbNetflux_Recieve.o_bPartnerSeqNumber // Provide feedback
);
```

## Commissioning and Tuning: The Key to Performance

Properly tuning the send interval is the most important step for creating a stable, high-performance link. The `fbNetflux_Statistics` block is designed specifically for this purpose.

**Goal:** Set the send interval of the faster PLC to be slightly *slower* than the average processing cycle of the slower PLC. This prevents overwhelming the slower partner and guarantees zero packet loss.

### Step-by-Step Tuning Guide

1. **Add the Statistics Block:** Instantiate `fbNetflux_Statistics` in your program and link its inputs to the `Send` and `Recieve` blocks.

    ```ST
    _fbNetflux_Statistics(
        i_rTaskCycle := _fbTaskInfo.rTaskCycle, // Provide your measured task time
        i_bRecvSeqNumber:= _fbNetflux_Recieve.o_bPartnerSeqNumber,
        i_bSequenceNumber:= _fbNetflux_Send.o_bSequenceNumber,
        i_bFeedBackSeqNumber:= _fbNetflux_Recieve.o_bCurrentFeedbackSeqNumber
    );
    ```

2. **Monitor Partner Packet Loss:** Go online and observe `_fbNetflux_Statistics.o_bTotalPartnerLostPackets`.
    - **This value MUST be 0.**
    - If you see any losses, it means you are sending data too frequently. You MUST increase the send interval inside your `fbNetflux_Send` block.

3. **Analyze Partner Speed:** Observe `_fbNetflux_Statistics.o_rAvgPartnerInterval`.
    - This value shows you the true, average processing time of the remote PLC, including its task jitter. This is the most important number for tuning.

4. **Set the Final Send Interval:**
    - In your `fbNetflux_Send` block, set the send interval (`i_tSendInterval`) to be slightly longer than the measured `o_rAvgPartnerInterval`.
    - **Formula:** `Send Interval = o_rAvgPartnerInterval + Safety Margin` (e.g., 1-2 ms).
    - This ensures that you never send data faster than the partner can handle, resulting in a perfectly stable connection.

## Performance Example

> Between two CODESYS PLCs running in a **1ms cyclic task**, this protocol successfully achieved a stable **1ms data exchange rate**. The watchdog was configured to `T#4MS`. This demonstrates its capability for very high-speed, real-time applications.
