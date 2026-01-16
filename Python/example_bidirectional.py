"""
Netflux Example - Bidirectional Communication Test

This example demonstrates bidirectional communication between two Netflux instances.
One acts as "Device A" and the other as "Device B", simulating the PLC-to-PLC
communication from the CODESYS implementation.

Author: Converted from CODESYS implementation
"""

import time
import threading
from netflux_main import NetfluxMain


def run_device_a():
    """Run Device A (simulates first PLC)."""
    print("\n[Device A] Starting...")
    
    device_a = NetfluxMain(
        local_port=2000,
        remote_ip='127.0.0.1',
        remote_port=2001,
        send_interval=0.005,    # 5ms
        watch_interval=0.030    # 30ms
    )
    
    if not device_a.start():
        print("[Device A] Failed to start!")
        return
    
    try:
        counter = 0
        while True:
            time.sleep(1.0)
            
            # Update send data
            device_a.set_send_data(
                value1=counter * 1.1,
                value2=counter * 2.2,
                value3=counter,
                value4=1000 + counter,
                flags=0xA0 | (counter % 16)
            )
            
            # Print status every 5 seconds
            if counter % 5 == 0:
                print("\n" + "="*60)
                print("DEVICE A STATUS")
                device_a.print_status()
                
                # Show what we received from Device B
                recv_data = device_a.get_recv_data()
                print(f"[Device A] Received from B: {recv_data}")
            
            counter += 1
            
    except KeyboardInterrupt:
        print("\n[Device A] Interrupted")
    finally:
        device_a.stop()


def run_device_b():
    """Run Device B (simulates second PLC)."""
    print("\n[Device B] Starting...")
    
    device_b = NetfluxMain(
        local_port=2001,
        remote_ip='127.0.0.1',
        remote_port=2000,
        send_interval=0.005,    # 5ms
        watch_interval=0.030    # 30ms
    )
    
    if not device_b.start():
        print("[Device B] Failed to start!")
        return
    
    try:
        counter = 0
        while True:
            time.sleep(1.0)
            
            # Update send data (different pattern than Device A)
            device_b.set_send_data(
                value1=counter * 3.3,
                value2=counter * 4.4,
                value3=counter * 2,
                value4=2000 + counter,
                flags=0xB0 | (counter % 16)
            )
            
            # Print status every 5 seconds (offset by 2.5s from Device A)
            if counter % 5 == 2:
                print("\n" + "="*60)
                print("DEVICE B STATUS")
                device_b.print_status()
                
                # Show what we received from Device A
                recv_data = device_b.get_recv_data()
                print(f"[Device B] Received from A: {recv_data}")
            
            counter += 1
            
    except KeyboardInterrupt:
        print("\n[Device B] Interrupted")
    finally:
        device_b.stop()


def main():
    """Run both devices in separate threads."""
    print("="*60)
    print("NETFLUX BIDIRECTIONAL COMMUNICATION TEST")
    print("="*60)
    print("\nThis example runs two Netflux instances communicating with each other.")
    print("Device A listens on port 2000 and sends to port 2001")
    print("Device B listens on port 2001 and sends to port 2000")
    print("\nPress Ctrl+C to stop.\n")
    
    # Create threads for both devices
    thread_a = threading.Thread(target=run_device_a, daemon=False)
    thread_b = threading.Thread(target=run_device_b, daemon=False)
    
    # Start both devices
    thread_a.start()
    time.sleep(0.5)  # Small delay to let Device A start first
    thread_b.start()
    
    # Wait for both threads
    try:
        thread_a.join()
        thread_b.join()
    except KeyboardInterrupt:
        print("\n\nShutting down both devices...")


if __name__ == '__main__':
    main()
