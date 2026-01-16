"""
Netflux Receiver Module

This module implements the receiving part of the Netflux UDP communication protocol.
It manages UDP reception with sequence number validation, watchdog timeout detection,
and duplicate packet filtering.

Expected UDP Payload Structure:
    - Byte 0: Sequence Number (0-255, rolls over)
    - Byte 1: Feedback Sequence Number (sender's received sequence number)
    - Byte 2...N: Actual data payload

Author: Converted from CODESYS implementation
"""

import socket
import struct
import time
import threading
from typing import Callable, Optional, Any
from dataclasses import dataclass


@dataclass
class ReceiverStats:
    """Statistics for the receiver"""
    first_packet_received: bool = False
    last_valid_packet_time: float = 0.0
    watchdog_timeout: bool = False
    total_packets_received: int = 0
    total_packets_rejected: int = 0


class NetfluxReceiver:
    """
    Manages the receiving part of UDP communication with sequence number validation
    and watchdog timeout detection.
    """
    
    def __init__(
        self,
        local_port: int,
        data_callback: Callable[[bytes], None],
        data_size: int,
        watch_interval: float = 1.0,
        keep_values_on_timeout: bool = False
    ):
        """
        Initialize the Netflux Receiver.
        
        Args:
            local_port: Local UDP port to listen on
            data_callback: Callback function to handle received data payload
            data_size: Expected size of data payload (excluding 2-byte header)
            watch_interval: Watchdog timeout in seconds (default: 1.0)
            keep_values_on_timeout: If True, keep last values on timeout; if False, clear them
        """
        self.local_port = local_port
        self.data_callback = data_callback
        self.data_size = data_size
        self.watch_interval = watch_interval
        self.keep_values_on_timeout = keep_values_on_timeout
        
        # Internal state
        self._socket: Optional[socket.socket] = None
        self._running = False
        self._receive_thread: Optional[threading.Thread] = None
        
        # Sequence number tracking
        self._previous_recv_seq_number: int = 0
        self._previous_feedback_seq_number: int = 0
        
        # Output values
        self.partner_seq_number: int = 0
        self.current_feedback_seq_number: int = 0
        self.error: bool = True
        self.error_message: str = "Not started"
        
        # Statistics
        self.stats = ReceiverStats()
        
        # Last received data buffer
        self._last_data: bytes = b'\x00' * data_size
        
        # Thread synchronization
        self._lock = threading.Lock()
    
    def start(self) -> bool:
        """
        Start the receiver and begin listening for UDP packets.
        
        Returns:
            True if started successfully, False otherwise
        """
        try:
            # Create UDP socket
            self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self._socket.bind(('', self.local_port))
            self._socket.settimeout(0.1)  # Non-blocking with timeout
            
            # Start receive thread
            self._running = True
            self._receive_thread = threading.Thread(target=self._receive_loop, daemon=True)
            self._receive_thread.start()
            
            self.error_message = ""
            return True
            
        except Exception as e:
            self.error = True
            self.error_message = f"Failed to start receiver: {e}"
            return False
    
    def stop(self):
        """Stop the receiver and close the socket."""
        self._running = False
        
        if self._receive_thread:
            self._receive_thread.join(timeout=2.0)
        
        if self._socket:
            self._socket.close()
            self._socket = None
    
    def _is_new_packet(self, recv_seq: int) -> bool:
        """
        Check if the received sequence number represents a new packet.
        Handles 8-bit counter wrap-around (0-255).
        
        Args:
            recv_seq: Received sequence number
            
        Returns:
            True if this is a new packet, False otherwise
        """
        if not self.stats.first_packet_received:
            return True
        
        # Check if sequence number has advanced
        # Handle wrap-around: consider "new" if difference is small and positive,
        # or if it wrapped around (large negative difference)
        diff = (recv_seq - self._previous_recv_seq_number) & 0xFF
        
        # Packet is new if difference is between 1 and 127 (half the range)
        return 1 <= diff < 128
    
    def _receive_loop(self):
        """Main receive loop running in a separate thread."""
        recv_buffer = bytearray(1460)  # Maximum UDP payload size
        
        while self._running:
            try:
                # Try to receive data
                try:
                    num_bytes, addr = self._socket.recvfrom_into(recv_buffer)
                except socket.timeout:
                    # Check watchdog timeout
                    self._check_watchdog()
                    continue
                
                if num_bytes < 2 + self.data_size:
                    # Packet too small
                    with self._lock:
                        self.stats.total_packets_rejected += 1
                    continue
                
                # Extract header
                recv_seq_number = recv_buffer[0]
                feedback_seq_number = recv_buffer[1]
                
                # Check if this is a new packet
                with self._lock:
                    # Update partner sequence number immediately
                    self.partner_seq_number = recv_seq_number
                    
                    if recv_seq_number != self._previous_recv_seq_number:
                        if self._is_new_packet(recv_seq_number):
                            # Valid new packet - process it
                            self.stats.first_packet_received = True
                            self.stats.last_valid_packet_time = time.time()
                            self.stats.total_packets_received += 1
                            
                            # Store feedback sequence number
                            self.current_feedback_seq_number = feedback_seq_number
                            
                            # Extract data payload
                            data_payload = bytes(recv_buffer[2:2 + self.data_size])
                            self._last_data = data_payload
                            
                            # Update previous sequence number
                            self._previous_recv_seq_number = recv_seq_number
                            
                            # Call user callback with data
                            try:
                                self.data_callback(data_payload)
                            except Exception as e:
                                print(f"Error in data callback: {e}")
                            
                            # Clear error if we received valid data
                            self.error = False
                            self.error_message = ""
                        else:
                            # Old/duplicate packet - reject
                            self.stats.total_packets_rejected += 1
                
            except Exception as e:
                if self._running:
                    self.error = True
                    self.error_message = f"Receive error: {e}"
    
    def _check_watchdog(self):
        """Check if watchdog timeout has occurred."""
        with self._lock:
            if not self.stats.first_packet_received:
                self.error = True
                self.error_message = "No valid packet received yet"
                return
            
            # Check if feedback sequence number has changed
            feedback_changed = (
                self.current_feedback_seq_number != self._previous_feedback_seq_number
            )
            
            if feedback_changed:
                # Connection is alive - reset watchdog
                self.stats.last_valid_packet_time = time.time()
                self._previous_feedback_seq_number = self.current_feedback_seq_number
                self.stats.watchdog_timeout = False
                return
            
            # Check timeout
            time_since_last = time.time() - self.stats.last_valid_packet_time
            
            if time_since_last > self.watch_interval:
                # Watchdog timeout occurred
                self.stats.watchdog_timeout = True
                self.error = True
                self.error_message = f"Watchdog timeout ({time_since_last:.2f}s)"
                
                # Handle timeout behavior
                if not self.keep_values_on_timeout:
                    # Clear data buffer
                    self._last_data = b'\x00' * self.data_size
                    self.stats.first_packet_received = False
                    
                    # Notify callback with cleared data
                    try:
                        self.data_callback(self._last_data)
                    except Exception as e:
                        print(f"Error in data callback: {e}")
    
    def get_last_data(self) -> bytes:
        """
        Get the last received data payload.
        
        Returns:
            Last received data as bytes
        """
        with self._lock:
            return self._last_data
    
    def get_stats(self) -> ReceiverStats:
        """
        Get receiver statistics.
        
        Returns:
            Copy of current statistics
        """
        with self._lock:
            return ReceiverStats(
                first_packet_received=self.stats.first_packet_received,
                last_valid_packet_time=self.stats.last_valid_packet_time,
                watchdog_timeout=self.stats.watchdog_timeout,
                total_packets_received=self.stats.total_packets_received,
                total_packets_rejected=self.stats.total_packets_rejected
            )
