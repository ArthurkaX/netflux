"""
Netflux - Robust UDP Communication Protocol

A Python implementation of the Netflux UDP communication protocol,
converted from the CODESYS implementation.

Features:
- Sequence number validation with wrap-around handling
- Feedback mechanism for acknowledgments
- Watchdog timeout detection
- Statistics tracking (intervals, RTT, packet loss)
- Thread-safe bidirectional communication

Example usage:
    from netflux import NetfluxMain
    
    netflux = NetfluxMain(
        local_port=2000,
        remote_ip='192.168.1.100',
        remote_port=2000
    )
    
    netflux.start()
    netflux.set_send_data(value1=123.45, value2=678.90)
    recv_data = netflux.get_recv_data()
    netflux.stop()

Author: Converted from CODESYS implementation
Version: 1.0.0
"""

from .netflux_receiver import NetfluxReceiver, ReceiverStats
from .netflux_sender import NetfluxSender, SenderStats
from .netflux_statistics import NetfluxStatisticsTracker, NetfluxStatistics
from .netflux_main import NetfluxMain, NetfluxData

__version__ = '1.0.0'
__author__ = 'Converted from CODESYS implementation'

__all__ = [
    'NetfluxMain',
    'NetfluxData',
    'NetfluxReceiver',
    'NetfluxSender',
    'NetfluxStatisticsTracker',
    'NetfluxStatistics',
    'ReceiverStats',
    'SenderStats',
]
