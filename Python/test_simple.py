"""
Netflux Simple Test

A simple test to verify the Netflux implementation works correctly.
This creates a single instance that sends to itself (loopback test).

Author: Converted from CODESYS implementation
"""

import time
from netflux_main import NetfluxMain


def main():
    """Simple loopback test."""
    print("="*60)
    print("NETFLUX SIMPLE TEST")
    print("="*60)
    print("\nThis test creates a single Netflux instance that")
    print("sends data to itself via loopback (127.0.0.1).")
    print("\nPress Ctrl+C to stop.\n")
    
    # Create Netflux instance (send and receive on same port via loopback)
    netflux = NetfluxMain(
        local_port=2000,
        remote_ip='127.0.0.1',
        remote_port=2000,
        send_interval=0.004,    # 4ms
        watch_interval=0.010    # 10ms
    )
    
    # Start
    if not netflux.start():
        print("Failed to start Netflux!")
        return
    
    print("\nRunning test for 30 seconds...\n")
    
    try:
        # Run for 30 seconds
        for i in range(30):
            time.sleep(1.0)
            
            # Update send data
            netflux.set_send_data(
                value1=i * 1.5,
                value2=i * 2.5,
                value3=i,
                value4=i * 100,
                flags=i % 256
            )
            
            # Get received data
            recv_data = netflux.get_recv_data()
            
            # Print progress
            print(f"[{i+1:2d}/30] Sent: value3={i}, Recv: value3={recv_data.value3}, "
                  f"Seq: {netflux.sender.sequence_number}, "
                  f"Recv Seq: {netflux.receiver.partner_seq_number}")
            
            # Print detailed status every 10 seconds
            if (i + 1) % 10 == 0:
                netflux.print_status()
        
        print("\n" + "="*60)
        print("TEST COMPLETED SUCCESSFULLY!")
        print("="*60)
        
        # Final status
        netflux.print_status()
        
        # Verify we received data
        recv_stats = netflux.receiver.get_stats()
        send_stats = netflux.sender.get_stats()
        
        print("\nTest Results:")
        print(f"  ✓ Packets sent: {send_stats.total_packets_sent}")
        print(f"  ✓ Packets received: {recv_stats.total_packets_received}")
        print(f"  ✓ Packets rejected: {recv_stats.total_packets_rejected}")
        print(f"  ✓ Send errors: {send_stats.total_send_errors}")
        
        if recv_stats.total_packets_received > 0:
            print("\n✓ Communication working correctly!")
        else:
            print("\n✗ WARNING: No packets received!")
        
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    finally:
        netflux.stop()


if __name__ == '__main__':
    main()
