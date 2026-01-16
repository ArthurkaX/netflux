# Netflux Python Implementation

This directory contains a Python implementation of the **Netflux** UDP communication protocol, converted from the CODESYS implementation.

## Overview

Netflux is a robust UDP-based communication protocol designed for real-time bidirectional data exchange between devices (e.g., PLCs, computers). It features:

- **Sequence Number Validation**: Detects and rejects duplicate or out-of-order packets
- **Feedback Mechanism**: Acknowledges received packets for reliability tracking
- **Watchdog Timeout**: Detects communication loss
- **Statistics Tracking**: Monitors intervals, round-trip time (RTT), and packet loss
- **Thread-Safe**: Designed for concurrent send/receive operations

## Protocol Structure

Each UDP packet consists of:

```
Byte 0: Sequence Number (0-255, rolls over)
Byte 1: Feedback Sequence Number (acknowledgment)
Byte 2-N: Data Payload
```

## Files

- **`netflux_receiver.py`**: Receives UDP packets with sequence validation and watchdog
- **`netflux_sender.py`**: Sends UDP packets periodically with sequence numbering
- **`netflux_statistics.py`**: Tracks communication statistics (intervals, RTT, packet loss)
- **`netflux_main.py`**: Main application integrating all components
- **`example_bidirectional.py`**: Example demonstrating two-way communication

## Quick Start

### Basic Usage

```python
from netflux_main import NetfluxMain

# Create Netflux instance
netflux = NetfluxMain(
    local_port=2000,
    remote_ip='192.168.1.100',
    remote_port=2000,
    send_interval=0.005,    # 5ms
    watch_interval=0.030    # 30ms watchdog
)

# Start communication
netflux.start()

# Update data to send
netflux.set_send_data(
    value1=123.45,
    value2=678.90,
    value3=42,
    value4=1000,
    flags=0xAB
)

# Get received data
recv_data = netflux.get_recv_data()
print(f"Received: {recv_data}")

# Print status
netflux.print_status()

# Stop when done
netflux.stop()
```

### Running the Example

To test bidirectional communication between two instances on the same machine:

```bash
python example_bidirectional.py
```

This runs two Netflux instances:
- **Device A**: Listens on port 2000, sends to port 2001
- **Device B**: Listens on port 2001, sends to port 2000

## Customizing Data Structure

The default `NetfluxData` class in `netflux_main.py` contains example fields. Customize it for your application:

```python
@dataclass
class NetfluxData:
    # Your custom fields
    temperature: float = 0.0
    pressure: float = 0.0
    status: int = 0
    
    def to_bytes(self) -> bytes:
        # Pack your data
        return struct.pack('<ffI', self.temperature, self.pressure, self.status)
    
    @classmethod
    def from_bytes(cls, data: bytes) -> 'NetfluxData':
        # Unpack your data
        values = struct.unpack('<ffI', data[:12])
        return cls(temperature=values[0], pressure=values[1], status=values[2])
    
    @staticmethod
    def get_size() -> int:
        return 12  # Total bytes
```

## Architecture

### Receiver (`NetfluxReceiver`)

- Listens for incoming UDP packets
- Validates sequence numbers (handles wrap-around)
- Rejects duplicate/old packets
- Monitors watchdog timeout
- Thread-safe callback for received data

### Sender (`NetfluxSender`)

- Sends UDP packets at specified interval
- Increments sequence number (0-255, rolls over)
- Includes feedback sequence number
- Thread-safe data provider callback

### Statistics (`NetfluxStatisticsTracker`)

Calculates:
- **Average Intervals**: Time between packets (send/receive)
- **Round-Trip Time (RTT)**: Time from send to acknowledgment
- **Packet Loss**: Detected by gaps in sequence numbers

### Main Application (`NetfluxMain`)

Integrates receiver, sender, and statistics:
- Manages lifecycle (start/stop)
- Links feedback between sender and receiver
- Provides simple API for data exchange

## Configuration Parameters

| Parameter | Description | Default | CODESYS Equivalent |
|-----------|-------------|---------|-------------------|
| `local_port` | UDP port to listen on | 2000 | `i_uiLocalPort` |
| `remote_ip` | Remote device IP address | '172.10.10.10' | `i_sIPaddress` |
| `remote_port` | Remote device UDP port | 2000 | `i_uiRemotePort` |
| `send_interval` | Time between sends (seconds) | 0.005 (5ms) | `i_tSendInterval` |
| `watch_interval` | Watchdog timeout (seconds) | 0.030 (30ms) | `i_tWatchInterval` |
| `keep_values_on_timeout` | Keep last values on timeout | False | `i_xKeepValuesOnTimeout` |

## Error Handling

Both receiver and sender expose error status:

```python
if netflux.receiver.error:
    print(f"Receiver error: {netflux.receiver.error_message}")

if netflux.sender.error:
    print(f"Sender error: {netflux.sender.error_message}")
```

## Statistics Monitoring

```python
stats = netflux.statistics.get_stats()

print(f"Partner interval: {stats.avg_partner_interval:.2f} ms")
print(f"Own interval: {stats.avg_own_interval:.2f} ms")
print(f"RTT: {stats.last_rtt:.2f} ms")
print(f"Partner lost packets: {stats.total_partner_lost_packets}")
print(f"Feedback lost packets: {stats.total_feedback_lost_packets}")
```

## Thread Safety

All components are thread-safe:
- Receiver runs in its own thread
- Sender runs in its own thread
- Statistics updates run in a separate thread
- All shared data is protected by locks

## Comparison with CODESYS Implementation

| Feature | CODESYS | Python |
|---------|---------|--------|
| Language | Structured Text | Python 3 |
| UDP Library | NBS.UDP_* | socket |
| Threading | PLC cycle-based | threading module |
| Timing | TON function blocks | time.time() |
| Memory Operations | MEMUtils | struct, bytearray |
| Data Structures | VAR/VAR_INPUT/VAR_OUTPUT | dataclasses |

## Requirements

- Python 3.7+
- Standard library only (no external dependencies)

## License

Same as the parent Netflux project.

## Author

Converted from CODESYS implementation to Python.
