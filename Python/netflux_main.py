"""
Netflux Main Module

This is the main module that demonstrates the usage of the Netflux protocol.
It establishes bidirectional UDP communication with sequence numbers, feedback,
and statistics tracking.

This module mirrors the functionality of MAIN_NETFLUX.st from the CODESYS implementation.

Author: Converted from CODESYS implementation
"""

import time
import struct
import threading
from typing import Dict, Any
from dataclasses import dataclass, field

from netflux_receiver import NetfluxReceiver
from netflux_sender import NetfluxSender
from netflux_statistics import NetfluxStatisticsTracker


@dataclass
class NetfluxData:
    """
    Data structure for send/receive.
    Customize this to match your application's data structure.
    """
    # Example fields - modify as needed
    value1: float = 0.0
    value2: float = 0.0
    value3: int = 0
    value4: int = 0
    flags: int = 0
    
    def to_bytes(self) -> bytes:
        """Convert data structure to bytes for transmission."""
        # Pack as: 2 floats (4 bytes each) + 3 integers (4 bytes each) = 20 bytes
        return struct.pack('<ffIII', 
                          self.value1, 
                          self.value2, 
                          self.value3, 
                          self.value4, 
                          self.flags)
    
    @classmethod
    def from_bytes(cls, data: bytes) -> 'NetfluxData':
        """Create data structure from received bytes."""
        if len(data) < 20:
            # Pad with zeros if too short
            data = data + b'\x00' * (20 - len(data))
        
        values = struct.unpack('<ffIII', data[:20])
        return cls(
            value1=values[0],
            value2=values[1],
            value3=values[2],
            value4=values[3],
            flags=values[4]
        )
    
    @staticmethod
    def get_size() -> int:
        """Get the size of the data structure in bytes."""
        return 20


class NetfluxMain:
    """
    Main Netflux application class.
    Manages bidirectional UDP communication with a remote partner.
    """
    
    def __init__(
        self,
        local_port: int = 2000,
        remote_ip: str = '172.10.10.10',
        remote_port: int = 2000,
        send_interval: float = 0.005,  # 5ms
        watch_interval: float = 0.030,  # 30ms
        keep_values_on_timeout: bool = False
    ):
        """
        Initialize the Netflux application.
        
        Args:
            local_port: Local UDP port to listen on
            remote_ip: IP address of remote partner
            remote_port: UDP port of remote partner
            send_interval: Interval between sends in seconds
            watch_interval: Watchdog timeout in seconds
            keep_values_on_timeout: Keep last values on timeout if True
        """
        self.local_port = local_port
        self.remote_ip = remote_ip
        self.remote_port = remote_port
        self.send_interval = send_interval
        self.watch_interval = watch_interval
        
        # Data structures
        self.data_recv = NetfluxData()
        self.data_send = NetfluxData()
        
        # Netflux components
        self.receiver: NetfluxReceiver = None
        self.sender: NetfluxSender = None
        self.statistics: NetfluxStatisticsTracker = None
        
        # Running state
        self._running = False
        self._stats_thread: threading.Thread = None
        
        # Thread synchronization
        self._lock = threading.Lock()
        
        # Initialize components
        self._init_components(keep_values_on_timeout)
    
    def _init_components(self, keep_values_on_timeout: bool):
        """Initialize receiver, sender, and statistics components."""
        # Create receiver
        self.receiver = NetfluxReceiver(
            local_port=self.local_port,
            data_callback=self._on_data_received,
            data_size=NetfluxData.get_size(),
            watch_interval=self.watch_interval,
            keep_values_on_timeout=keep_values_on_timeout
        )
        
        # Create sender (will share socket with receiver)
        self.sender = NetfluxSender(
            remote_ip=self.remote_ip,
            remote_port=self.remote_port,
            data_provider=self._get_send_data,
            data_size=NetfluxData.get_size(),
            send_interval=self.send_interval,
            peer_socket=None  # Will be set after receiver starts
        )
        
        # Create statistics tracker
        # Estimate cycle time based on send interval
        cycle_time_ms = self.send_interval * 1000.0
        self.statistics = NetfluxStatisticsTracker(cycle_time_ms=cycle_time_ms)
    
    def _on_data_received(self, data: bytes):
        """
        Callback for when data is received.
        
        Args:
            data: Received data bytes
        """
        with self._lock:
            self.data_recv = NetfluxData.from_bytes(data)
    
    def _get_send_data(self) -> bytes:
        """
        Callback to get data to send.
        
        Returns:
            Data to send as bytes
        """
        with self._lock:
            return self.data_send.to_bytes()
    
    def _statistics_loop(self):
        """Update statistics periodically."""
        while self._running:
            try:
                # Update statistics
                self.statistics.update(
                    recv_seq_number=self.receiver.partner_seq_number,
                    send_seq_number=self.sender.sequence_number,
                    feedback_seq_number=self.receiver.current_feedback_seq_number
                )
                
                # Link receiver and sender (feedback loop)
                self.sender.set_partner_seq_number(self.receiver.partner_seq_number)
                
                # Sleep for cycle time
                time.sleep(self.send_interval)
                
            except Exception as e:
                print(f"Statistics update error: {e}")
    
    def start(self) -> bool:
        """
        Start the Netflux application.
        
        Returns:
            True if started successfully, False otherwise
        """
        print(f"Starting Netflux...")
        print(f"  Local port: {self.local_port}")
        print(f"  Remote: {self.remote_ip}:{self.remote_port}")
        print(f"  Send interval: {self.send_interval*1000:.1f}ms")
        print(f"  Watchdog timeout: {self.watch_interval*1000:.1f}ms")
        
        # Start receiver
        if not self.receiver.start():
            print(f"Failed to start receiver: {self.receiver.error_message}")
            return False
        
        print("✓ Receiver started")
        
        # Share socket with sender
        self.sender.peer_socket = self.receiver._socket
        
        # Start sender
        if not self.sender.start():
            print(f"Failed to start sender: {self.sender.error_message}")
            self.receiver.stop()
            return False
        
        print("✓ Sender started")
        
        # Start statistics thread
        self._running = True
        self._stats_thread = threading.Thread(target=self._statistics_loop, daemon=True)
        self._stats_thread.start()
        
        print("✓ Statistics tracker started")
        print("\nNetflux is running!")
        
        return True
    
    def stop(self):
        """Stop the Netflux application."""
        print("\nStopping Netflux...")
        
        self._running = False
        
        if self._stats_thread:
            self._stats_thread.join(timeout=2.0)
        
        if self.sender:
            self.sender.stop()
            print("✓ Sender stopped")
        
        if self.receiver:
            self.receiver.stop()
            print("✓ Receiver stopped")
        
        print("Netflux stopped.")
    
    def set_send_data(self, **kwargs):
        """
        Set data to send.
        
        Args:
            **kwargs: Field names and values to update
        """
        with self._lock:
            for key, value in kwargs.items():
                if hasattr(self.data_send, key):
                    setattr(self.data_send, key, value)
    
    def get_recv_data(self) -> NetfluxData:
        """
        Get received data.
        
        Returns:
            Copy of received data
        """
        with self._lock:
            return NetfluxData(
                value1=self.data_recv.value1,
                value2=self.data_recv.value2,
                value3=self.data_recv.value3,
                value4=self.data_recv.value4,
                flags=self.data_recv.flags
            )
    
    def print_status(self):
        """Print current status and statistics."""
        print("\n" + "="*60)
        print("NETFLUX STATUS")
        print("="*60)
        
        # Receiver status
        print("\n[RECEIVER]")
        print(f"  Error: {self.receiver.error}")
        if self.receiver.error:
            print(f"  Error Message: {self.receiver.error_message}")
        print(f"  Partner Seq #: {self.receiver.partner_seq_number}")
        print(f"  Feedback Seq #: {self.receiver.current_feedback_seq_number}")
        
        recv_stats = self.receiver.get_stats()
        print(f"  Packets Received: {recv_stats.total_packets_received}")
        print(f"  Packets Rejected: {recv_stats.total_packets_rejected}")
        print(f"  Watchdog Timeout: {recv_stats.watchdog_timeout}")
        
        # Sender status
        print("\n[SENDER]")
        print(f"  Error: {self.sender.error}")
        if self.sender.error:
            print(f"  Error Message: {self.sender.error_message}")
        print(f"  Own Seq #: {self.sender.sequence_number}")
        
        send_stats = self.sender.get_stats()
        print(f"  Packets Sent: {send_stats.total_packets_sent}")
        print(f"  Send Errors: {send_stats.total_send_errors}")
        
        # Statistics
        print("\n[STATISTICS]")
        stats = self.statistics.get_stats()
        print(f"  Avg Partner Interval: {stats.avg_partner_interval:.2f} ms")
        print(f"  Avg Own Interval: {stats.avg_own_interval:.2f} ms")
        print(f"  Last RTT: {stats.last_rtt:.2f} ms")
        print(f"  Partner Lost Packets: {stats.total_partner_lost_packets}")
        print(f"  Feedback Lost Packets: {stats.total_feedback_lost_packets}")
        
        # Data
        print("\n[DATA]")
        print(f"  Send: {self.data_send}")
        print(f"  Recv: {self.data_recv}")
        
        print("="*60 + "\n")


def main():
    """Example usage of Netflux."""
    # Create Netflux instance
    netflux = NetfluxMain(
        local_port=2000,
        remote_ip='127.0.0.1',  # Loopback for testing
        remote_port=2001,
        send_interval=0.005,     # 5ms
        watch_interval=0.030     # 30ms
    )
    
    # Start
    if not netflux.start():
        print("Failed to start Netflux!")
        return
    
    try:
        # Run for a while, updating send data
        counter = 0
        while True:
            time.sleep(1.0)
            
            # Update send data
            netflux.set_send_data(
                value1=counter * 1.5,
                value2=counter * 2.5,
                value3=counter,
                value4=counter * 10,
                flags=counter % 256
            )
            
            # Print status every 5 seconds
            if counter % 5 == 0:
                netflux.print_status()
            
            counter += 1
            
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    finally:
        netflux.stop()


if __name__ == '__main__':
    main()
