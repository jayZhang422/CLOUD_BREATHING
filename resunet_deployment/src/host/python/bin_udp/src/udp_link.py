"""UDP socket wrapper shared by the sender and the FPGA simulator."""

import socket

DEFAULT_BUFFER_BYTES = 4 * 1024 * 1024


class UdpPeer:
    """One bound UDP socket; hides the Windows ICMP port-unreachable quirk.

    On Windows, a previous sendto() to a closed UDP port surfaces as
    ConnectionResetError on a later recvfrom()/sendto(); both are treated as
    "no reply yet" so a receiver that starts slightly later does not kill the
    sender (the two processes are launched at the same time during testing).
    """

    def __init__(self, bind_addr: tuple[str, int],
                 buffer_bytes: int = DEFAULT_BUFFER_BYTES) -> None:
        self.bind_addr = bind_addr
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, buffer_bytes)
            self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, buffer_bytes)
            self._sock.bind(bind_addr)
        except OSError as exc:
            self._sock.close()
            raise OSError(
                f"cannot bind UDP {bind_addr[0]}:{bind_addr[1]}: {exc}; "
                "for a local loopback test use --bind 127.0.0.1:<port>"
            ) from exc
        self.resets = 0

    @property
    def local_addr(self) -> tuple[str, int]:
        return self._sock.getsockname()

    def sendto(self, data: bytes, addr: tuple[str, int]) -> None:
        try:
            self._sock.sendto(data, addr)
        except ConnectionResetError:
            self.resets += 1
        except OSError as exc:
            raise OSError(f"sendto({addr[0]}:{addr[1]}) failed: {exc}") from exc

    def recvfrom(self, timeout: float) -> tuple[bytes, tuple[str, int]] | None:
        """Return (data, addr), or None on timeout / ICMP reset."""
        self._sock.settimeout(timeout)
        try:
            return self._sock.recvfrom(65535)
        except (socket.timeout, ConnectionResetError):
            return None

    def close(self) -> None:
        self._sock.close()
