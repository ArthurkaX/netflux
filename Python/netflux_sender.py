"""
Netflux Sender Module

This module implements the sending part of the Netflux UDP communication protocol.
It manages periodic UDP packet transmission with sequence numbers and feedback.

UDP Payload Structure created by this module:
    - Byte 0: Own sequence number (incrementing, 0-255)
    - Byte 1: Partner's sequence number (feedback)
    - Byte 2...N: Actual data payload

Author: Converted from CODESYS implementation
"""

import socket
import struct
import time
import threading
from typing import Optional, Callable
from dataclasses import dataclass


@dataclass
class SenderStats:
    """Statistics for the sender"""
    total_packets_sent: int = 0
    total_send_errors: int = 0
    last_send_time: float = 0.0


class NetfluxSender:
    """
    Manages the sending part of UDP communication with sequence numbers
    and feedback mechanism.
    """
    
    def __init__(
        self,
        remote_ip: str,
        remote_port: int,
        data_provider: Callable[[], bytes],
        data_size: int,
        send_interval: float = 0.005,  # 5ms default
        peer_socket: Optional[socket.socket] = None
    ):
        """
        Initialize the Netflux Sender.
        
        Args:
            remote_ip: IP address of the remote partner
            remote_port: UDP port of the remote partner
            data_provider: Callback function that returns data to send
            data_size: Size of data payload to send
            send_interval: Interval between sends in seconds (default: 0.005 = 5ms)
            peer_socket: Optional shared socket from receiver (for bidirectional comm)
        """
        self.remote_ip = remote_ip
        self.remote_port = remote_port
        self.data_provider = data_provider
        self.data_size = data_size
        self.send_interval = send_interval
        self.peer_socket = peer_socket
        
        # Internal state
        self._socket: Optional[socket.socket] = None
        self._running = False
        self._send_thread: Optional[threading.Thread] = None
        
        # Sequence numbers
        self.sequence_number: int = 0
        self.partner_seq_number: int = 0
        
        # Output values
        self.error: bool = False
        self.error_message: str = ""
        
        # Statistics
        self.stats = SenderStats()
        
        # Thread synchronization
        self._lock = threading.Lock()
        
        # Send buffer
        self._send_buffer = bytearray(2 + data_size)
    
    def start(self) -> bool:
        """
        Start the sender and begin sending UDP packets.
        
        Returns:
            True if started successfully, False otherwise
        """
        try:
            # Use provided socket or create new one
            if self.peer_socket is None:
                self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            else:
                self._socket = self.peer_socket
            
            # Start send thread
            self._running = True
            self._send_thread = threading.Thread(target=self._send_loop, daemon=True)
            self._send_thread.start()
            
            return True
            
        except Exception as e:
            self.error = True
            self.error_message = f"Failed to start sender: {e}"
            return False
    
    def stop(self):
        """Stop the sender and close the socket if we own it."""
        self._running = False
        
        if self._send_thread:
            self._send_thread.join(timeout=2.0)
        
        # Only close socket if we created it (not shared from receiver)
        if self._socket and self.peer_socket is None:
            self._socket.close()
            self._socket = None
    
    def set_partner_seq_number(self, seq_num: int):
        """
        Update the partner's sequence number (for feedback).
        This should be called with the value from the receiver.
        
        Args:
            seq_num: Partner's sequence number
        """
        with self._lock:
            self.partner_seq_number = seq_num
    
    def _send_loop(self):
        """Main send loop running in a separate thread."""
        next_send_time = time.time()
        
        while self._running:
            current_time = time.time()
            
            # Check if it's time to send
            if current_time >= next_send_time:
                try:
                    self._send_packet()
                    next_send_time = current_time + self.send_interval
                except Exception as e:
                    with self._lock:
                        self.error = True
                        self.error_message = f"Send error: {e}"
                        self.stats.total_send_errors += 1
            
            # Sleep for a short time to avoid busy-waiting
            sleep_time = max(0.001, next_send_time - time.time())
            time.sleep(min(sleep_time, 0.001))
    
    def _send_packet(self):
        """Construct and send a single UDP packet."""
        with self._lock:
            # Increment sequence number
            self.sequence_number = (self.sequence_number + 1) & 0xFF
            
            # Construct header
            self._send_buffer[0] = self.sequence_number
            self._send_buffer[1] = self.partner_seq_number
            
            # Get data from provider
            try:
                data = self.data_provider()
                if len(data) != self.data_size:
                    raise ValueError(
                        f"Data provider returned {len(data)} bytes, expected {self.data_size}"
                    )
                self._send_buffer[2:2 + self.data_size] = data
            except Exception as e:
                self.error = True
                self.error_message = f"Data provider error: {e}"
                return
            
            # Send packet
            try:
                self._socket.sendto(
                    self._send_buffer,
                    (self.remote_ip, self.remote_port)
                )
                
                # Update statistics
                self.stats.total_packets_sent += 1
                self.stats.last_send_time = time.time()
                self.error = False
                self.error_message = ""
                
            except Exception as e:
                self.error = True
                self.error_message = f"Socket send error: {e}"
                self.stats.total_send_errors += 1
    
    def get_stats(self) -> SenderStats:
        """
        Get sender statistics.
        
        Returns:
            Copy of current statistics
        """
        with self._lock:
            return SenderStats(
                total_packets_sent=self.stats.total_packets_sent,
                total_send_errors=self.stats.total_send_errors,
                last_send_time=self.stats.last_send_time
            )
