"""
Netflux Statistics Module

This module calculates communication statistics for the Netflux protocol:
- Average send/receive intervals
- Round-trip time (RTT)
- Packet loss detection

Author: Converted from CODESYS implementation
"""

import time
import threading
from typing import Optional
from dataclasses import dataclass


@dataclass
class NetfluxStatistics:
    """Statistics data structure"""
    avg_partner_interval: float = 0.0  # Average time between received packets (ms)
    avg_own_interval: float = 0.0      # Average time between sent packets (ms)
    last_rtt: float = 0.0               # Last measured round-trip time (ms)
    total_partner_lost_packets: int = 0 # Packets lost from partner
    total_feedback_lost_packets: int = 0 # Acknowledgments lost


class NetfluxStatisticsTracker:
    """
    Tracks and calculates communication statistics for Netflux protocol.
    
    Calculates:
    - Intervals: Measured by timing a full sequence number cycle (0-255)
    - RTT: Measured by tracking a sequence number until acknowledgment
    - Packet Loss: Detected by gaps in sequence numbers
    """
    
    def __init__(self, cycle_time_ms: float = 1.0):
        """
        Initialize the statistics tracker.
        
        Args:
            cycle_time_ms: Task cycle time in milliseconds (for timing calculations)
        """
        self.cycle_time_ms = cycle_time_ms
        
        # Output statistics
        self.stats = NetfluxStatistics()
        
        # Own send interval tracking
        self._own_cycle_counter: float = 0.0
        self._prev_send_seq_number: int = 0
        
        # Partner interval tracking
        self._partner_cycle_counter: float = 0.0
        self._prev_recv_seq_number: int = 0
        
        # Feedback/packet loss tracking
        self._prev_feedback_seq_number: int = 0
        
        # RTT tracking
        self._rtt_counter: float = 0.0
        self._rtt_tracked_seq_num: int = 0
        
        # Timing
        self._last_update_time: float = time.time()
        
        # Thread synchronization
        self._lock = threading.Lock()
    
    def update(
        self,
        recv_seq_number: int,
        send_seq_number: int,
        feedback_seq_number: int
    ):
        """
        Update statistics with new sequence numbers.
        Should be called periodically (every cycle).
        
        Args:
            recv_seq_number: Sequence number from partner's last received packet
            send_seq_number: Own send sequence number
            feedback_seq_number: Feedback from partner (own seq number being returned)
        """
        with self._lock:
            # Calculate actual elapsed time since last update
            current_time = time.time()
            elapsed_ms = (current_time - self._last_update_time) * 1000.0
            self._last_update_time = current_time
            
            # Update own send interval
            self._update_own_interval(send_seq_number, elapsed_ms)
            
            # Update partner receive interval
            self._update_partner_interval(recv_seq_number, elapsed_ms)
            
            # Update packet loss statistics
            self._update_packet_loss(recv_seq_number, feedback_seq_number)
            
            # Update RTT
            self._update_rtt(send_seq_number, feedback_seq_number, elapsed_ms)
    
    def _update_own_interval(self, send_seq_number: int, elapsed_ms: float):
        """Update own send interval statistics."""
        # Check if sequence wrapped around (completed a cycle)
        if send_seq_number >= 0 and send_seq_number < 3:
            if self._prev_send_seq_number > 250:  # Wrapped around
                # Calculate average interval over 256 packets
                if self._own_cycle_counter > 0:
                    self.stats.avg_own_interval = (
                        self._own_cycle_counter / 256.0 - 2.0 * self.cycle_time_ms
                    )
                self._own_cycle_counter = 0.0
        
        self._own_cycle_counter += elapsed_ms
        self._prev_send_seq_number = send_seq_number
    
    def _update_partner_interval(self, recv_seq_number: int, elapsed_ms: float):
        """Update partner receive interval statistics."""
        # Check if sequence wrapped around (completed a cycle)
        if recv_seq_number >= 0 and recv_seq_number < 5:
            if self._prev_recv_seq_number > 250:  # Wrapped around
                # Calculate average interval over 256 packets
                if self._partner_cycle_counter > 0:
                    self.stats.avg_partner_interval = (
                        self._partner_cycle_counter / 256.0 - 2.0 * self.cycle_time_ms
                    )
                self._partner_cycle_counter = 0.0
        
        self._partner_cycle_counter += elapsed_ms
        self._prev_recv_seq_number = recv_seq_number
    
    def _update_packet_loss(self, recv_seq_number: int, feedback_seq_number: int):
        """Update packet loss statistics."""
        # Detect gaps in received sequence numbers (partner packet loss)
        recv_diff = (recv_seq_number - self._prev_recv_seq_number) & 0xFF
        if recv_diff > 1 and recv_diff < 128:  # Gap detected (not wrap-around)
            lost_packets = recv_diff - 1
            self.stats.total_partner_lost_packets += lost_packets
        
        # Reset counter on wrap-around
        if recv_seq_number >= 0 and recv_seq_number < 5:
            if self._prev_recv_seq_number > 250:
                self.stats.total_partner_lost_packets = 0
        
        # Detect gaps in feedback sequence numbers (acknowledgment loss)
        feedback_diff = (feedback_seq_number - self._prev_feedback_seq_number) & 0xFF
        if feedback_diff > 1 and feedback_diff < 128:  # Gap detected
            lost_acks = feedback_diff - 1
            self.stats.total_feedback_lost_packets += lost_acks
        
        # Reset counter on wrap-around
        if feedback_seq_number >= 0 and feedback_seq_number < 15:
            if self._prev_feedback_seq_number > 240:
                self.stats.total_feedback_lost_packets = 0
        
        self._prev_feedback_seq_number = feedback_seq_number
    
    def _update_rtt(
        self,
        send_seq_number: int,
        feedback_seq_number: int,
        elapsed_ms: float
    ):
        """Update round-trip time statistics."""
        # Start tracking a new sequence number when we're not tracking one
        if self._rtt_tracked_seq_num == 0:
            if send_seq_number != self._prev_send_seq_number:
                self._rtt_tracked_seq_num = send_seq_number
                self._rtt_counter = 0.0
        else:
            # Accumulate time
            self._rtt_counter += elapsed_ms
            
            # Check if we received acknowledgment for tracked sequence number
            if self._rtt_tracked_seq_num == feedback_seq_number:
                self.stats.last_rtt = self._rtt_counter
                self._rtt_tracked_seq_num = 0  # Reset for next measurement
    
    def reset(self):
        """Reset all statistics to initial values."""
        with self._lock:
            self.stats = NetfluxStatistics()
            self._own_cycle_counter = 0.0
            self._partner_cycle_counter = 0.0
            self._rtt_counter = 0.0
            self._rtt_tracked_seq_num = 0
            self._last_update_time = time.time()
    
    def get_stats(self) -> NetfluxStatistics:
        """
        Get current statistics.
        
        Returns:
            Copy of current statistics
        """
        with self._lock:
            return NetfluxStatistics(
                avg_partner_interval=self.stats.avg_partner_interval,
                avg_own_interval=self.stats.avg_own_interval,
                last_rtt=self.stats.last_rtt,
                total_partner_lost_packets=self.stats.total_partner_lost_packets,
                total_feedback_lost_packets=self.stats.total_feedback_lost_packets
            )
