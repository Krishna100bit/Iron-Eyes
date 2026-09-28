"""
ble_client.py  —  IronLoop BLE GATT Client
──────────────────────────────────────────
Discovers and connects to the "IronLoop" peripheral, subscribes to the
Stream and Status characteristics, and issues commands.
"""

import asyncio
import logging
from typing import Callable, Optional
from bleak import BleakScanner, BleakClient
from bleak.backends.device import BLEDevice
from bleak.backends.scanner import AdvertisementData

from packet_parser import PacketParser, ParsedStreamBatch, ParsedStatusPacket

LOG = logging.getLogger("ironloop.ble")

# ── Service & Characteristic UUIDs ─────────────────────────────────────────
SERVICE_UUID     = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
STREAM_CHAR_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
CMD_CHAR_UUID    = "beb5483f-36e1-4688-b7f5-ea07361b26a8"
STATUS_CHAR_UUID = "beb54840-36e1-4688-b7f5-ea07361b26a8"

# Command Constants
CMD_START_SESSION = 0x01
CMD_STOP_SESSION  = 0x02
CMD_CALIBRATE     = 0x03
CMD_PING          = 0x04


class IronLoopBLEClient:
    """Async BLE Client for IronLoop Hardware."""

    def __init__(
        self,
        on_batch_cb: Optional[Callable[[ParsedStreamBatch], None]] = None,
        on_status_cb: Optional[Callable[[ParsedStatusPacket], None]] = None,
        target_name: str = "IronLoop",
    ):
        self.target_name = target_name
        self.parser = PacketParser()
        self.on_batch_cb = on_batch_cb
        self.on_status_cb = on_status_cb

        self.client: Optional[BleakClient] = None
        self.is_connected = False
        self._disconnect_event = asyncio.Event()

    def _is_target_device(self, device: BLEDevice, adv: AdvertisementData) -> bool:
        """Robust multi-field matcher across Windows BLE stacks."""
        # 1. Match device name
        if device.name and self.target_name.lower() in device.name.lower():
            return True
        # 2. Match advertisement local name
        if adv.local_name and self.target_name.lower() in adv.local_name.lower():
            return True
        # 3. Match advertised Service UUID
        if adv.service_uuids:
            target_uuid = SERVICE_UUID.lower()
            if any(u.lower() == target_uuid for u in adv.service_uuids):
                return True
        return False

    async def scan_and_connect(self, timeout_s: float = 15.0) -> bool:
        """Scan for device name 'IronLoop' or matching Service UUID and establish GATT connection."""
        LOG.info(f"Scanning for BLE peripheral '{self.target_name}' (timeout: {timeout_s}s)...")
        device = await BleakScanner.find_device_by_filter(
            self._is_target_device,
            timeout=timeout_s,
        )

        if not device:
            LOG.error(f"Device '{self.target_name}' not found within {timeout_s}s.")
            return False

        dev_name = device.name or self.target_name
        LOG.info(f"Found: {dev_name} ({device.address}). Connecting...")

        def _on_disconnect(client: BleakClient):
            LOG.warning("BLE Peripheral disconnected.")
            self.is_connected = False
            self._disconnect_event.set()

        self.client = BleakClient(device, disconnected_callback=_on_disconnect)
        await self.client.connect()
        self.is_connected = True
        LOG.info(f"Connected [OK] (MTU: {self.client.mtu_size} bytes)")

        # Subscribe to notifications
        await self._setup_subscriptions()
        return True

    async def _setup_subscriptions(self):
        """Subscribe to Stream and Status GATT characteristics."""
        if not self.client or not self.client.is_connected:
            return

        def _stream_handler(sender, data: bytearray):
            batch = self.parser.parse_stream_packet(bytes(data))
            if batch and self.on_batch_cb:
                self.on_batch_cb(batch)

        def _status_handler(sender, data: bytearray):
            status = self.parser.parse_status_packet(bytes(data))
            if status and self.on_status_cb:
                self.on_status_cb(status)

        LOG.info("Subscribing to Stream notifications...")
        await self.client.start_notify(STREAM_CHAR_UUID, _stream_handler)

        LOG.info("Subscribing to Status notifications...")
        await self.client.start_notify(STATUS_CHAR_UUID, _status_handler)
        LOG.info("Subscribed to all characteristics.")

    async def send_command(self, cmd_byte: int) -> bool:
        """Write single-byte command to Command Characteristic."""
        if not self.client or not self.client.is_connected:
            LOG.error("Cannot send command: BLE not connected.")
            return False

        try:
            await self.client.write_gatt_char(
                CMD_CHAR_UUID, bytearray([cmd_byte]), response=True
            )
            LOG.info(f"Sent Command: 0x{cmd_byte:02X}")
            return True
        except Exception as e:
            LOG.error(f"Failed to write command 0x{cmd_byte:02X}: {e}")
            return False

    async def disconnect(self):
        """Cleanly unsubscribe and disconnect."""
        if self.client and self.client.is_connected:
            try:
                await self.client.stop_notify(STREAM_CHAR_UUID)
                await self.client.stop_notify(STATUS_CHAR_UUID)
            except Exception:
                pass
            await self.client.disconnect()
            self.is_connected = False
            LOG.info("Disconnected cleanly.")
