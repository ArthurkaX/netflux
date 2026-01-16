# Netflux for Siemens S7-1500

A complete Siemens S7-1500 implementation of the Netflux protocol is available here. This implementation is written in **SCL (Structured Control Language)** and provides full compatibility with the CODESYS version, enabling seamless cross-platform communication.

## Features

The Siemens implementation provides the same core functionality as the CODESYS version:

- ✓ High-speed UDP communication using TSEND_C/TRCV_C instructions
- ✓ Sequence number validation with wrap-around handling (0-255)
- ✓ Feedback mechanism for bidirectional acknowledgments
- ✓ Watchdog timeout detection with configurable intervals
- ✓ Automatic handling of out-of-order and duplicate packets
- ✓ Direct DB-to-DB data transfer (no intermediate variables needed)
- ✓ Configurable data retention on communication loss
- ✓ Comprehensive status and error reporting

## Files Included

| File | Description |
|------|-------------|
| `fbNetflux_SEND.scl` | Function block for sending data via UDP |
| `fbNetflux_RECV.scl` | Function block for receiving data via UDP |
| `MainOB1.scl` | Example main program showing proper usage |

## Quick Start

### 1. Create Data Blocks

First, create two data blocks for your send and receive data:
- `DB230` - Data to send (optimized access **disabled**)
- `DB231` - Data to receive (optimized access **disabled**)

**Important:** Both DBs must have "Optimized block access" disabled in TIA Portal.

### 2. Configure UDP Connection

In your device configuration, create a UDP connection and note the Connection ID (e.g., 257).

### 3. Implement in Main Program

```scl
ORGANIZATION_BLOCK "Main"
{ S7_Optimized_Access := 'TRUE' }
VERSION : 0.1

BEGIN
    // 1. Call Send block first (prepares outgoing packet)
    "fbNetflux_SEND_DB"(
        i_udp_connection_id := 257,
        i_ip_address := '192.168.10.10',
        i_udp_port := 2000,
        i_seq_num_partner := "fbNetflux_RECV_DB".o_seq_num_partner,
        i_send_DB_number := 230,
        i_send_rate := T#2ms
    );
    
    // 2. Your application logic goes here
    // Process received data from DB231
    // Prepare data to send in DB230
    
    // 3. Call Receive block last (processes incoming packet)
    "fbNetflux_RECV_DB"(
        i_udp_connection_id := 257,
        i_udp_port := 2000,
        i_recv_DB_number := 231,
        i_watch_interval := T#10ms
    );
    
END_ORGANIZATION_BLOCK
```

## Key Parameters

**fbNetflux_SEND:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `i_udp_connection_id` | CONN_OUC | Connection ID from device configuration |
| `i_ip_address` | String[15] | Partner IP address (e.g., '192.168.1.100') |
| `i_udp_port` | UInt | Partner UDP port number |
| `i_send_DB_number` | UInt | DB number containing data to send |
| `i_send_rate` | Time | Send interval (e.g., T#2ms) |
| `i_seq_num_partner` | USInt | Sequence number from receive block |
| `o_status` | Word | Detailed status code (see below) |
| `o_seq_num` | USInt | Current sequence number (0-255) |
| `o_error` | Bool | TRUE if any error occurs |

**fbNetflux_RECV:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `i_udp_connection_id` | CONN_OUC | Connection ID from device configuration |
| `i_udp_port` | UInt | Local UDP port to listen on |
| `i_recv_DB_number` | UInt | DB number where received data is stored |
| `i_watch_interval` | Time | Watchdog timeout (e.g., T#10ms) |
| `i_keep_values` | Bool | If TRUE, retain last values on timeout |
| `o_error` | Bool | TRUE if no valid data or timeout |
| `o_seq_num_partner` | USInt | Partner's sequence number |

## Status Codes (fbNetflux_SEND)

| Code | Description |
|------|-------------|
| `16#7000` | Idle - waiting for next send interval |
| `16#7001` | Initializing - first scan logic |
| `16#7002` | Preparing data - copying from DB |
| `16#7003` | Sending data - TSEND_C busy |
| `16#7004` | Send complete - waiting for next cycle |
| `16#8001` | Error - ATTR_DB failed (check DB number) |
| `16#8002` | Error - Send DB too large (max 1461 bytes) |
| `16#8003` | Error - Invalid IP address format |

## Important Notes

**Data Block Requirements:**
- Maximum data size: **1461 bytes** per direction
- Both send and receive DBs must have **optimized access disabled**
- DBs are accessed using PEEK/POKE instructions for maximum flexibility

**Sequence Number Logic:**
- Uses 8-bit sequence numbers (0-255) with automatic wrap-around
- Implements a 128-value sliding window for out-of-order detection
- Old or duplicate packets are automatically discarded

**Watchdog Behavior:**
- The receive block monitors the feedback sequence number
- If no new packet arrives within `i_watch_interval`, `o_error` is set to TRUE
- When `i_keep_values = FALSE`, the receive DB is cleared on timeout
- When `i_keep_values = TRUE`, last valid data is retained

**Performance:**
- Tested successfully at **2ms cycle time** between S7-1500 PLCs
- Can achieve **1ms** with proper network configuration and tuning
- Use the statistics approach from CODESYS version for optimal tuning

## Differences from CODESYS Version

| Aspect | CODESYS | Siemens S7-1500 |
|--------|---------|-----------------|
| Language | Structured Text (ST) | Structured Control Language (SCL) |
| UDP Instructions | `SocketSendTo`, `SocketReceiveFrom` | `TSEND_C`, `TRCV_C` |
| Data Access | Direct pointer access | PEEK/POKE instructions |
| Connection Setup | Runtime socket creation | Pre-configured connection ID |
| Statistics Block | Included (`fbNetflux_Statistics`) | Not yet implemented |
| Maximum Data Size | Configurable | 1461 bytes fixed |

## Example: S7-1500 to CODESYS Communication

**S7-1500 Side:**
```scl
// Send to CODESYS PLC at 192.168.1.50
"fbNetflux_SEND_DB"(
    i_ip_address := '192.168.1.50',
    i_udp_port := 2000,
    i_send_rate := T#5ms
);
```

**CODESYS Side:**
```ST
// Receive from S7-1500
_fbNetflux_Recieve(
    i_uiLocalPort := 2000,
    i_tWatchInterval := T#15MS
);
```

## Troubleshooting

**Communication not working:**
1. Verify UDP connection is configured in TIA Portal device configuration
2. Check that both DBs have optimized access disabled
3. Ensure firewall allows UDP traffic on specified port
4. Verify IP addresses and port numbers match on both sides

**Frequent timeouts:**
1. Increase `i_watch_interval` (recommend 3-5x the send rate)
2. Check network latency and packet loss
3. Verify send rate is not too fast for partner PLC cycle time

**Status code 16#8002:**
1. Your data DB is larger than 1461 bytes
2. Reduce data size or split into multiple connections
