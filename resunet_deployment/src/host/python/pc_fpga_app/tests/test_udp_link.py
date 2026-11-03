import unittest
from unittest.mock import patch

from pc_fpga.ethernet.udp_link import SEND_BUFFER_RETRIES, UdpPeer


class FakeSocket:
    def __init__(self, failures):
        self.failures = failures
        self.send_calls = 0

    def setsockopt(self, *args):
        pass

    def bind(self, addr):
        pass

    def sendto(self, data, addr):
        self.send_calls += 1
        if self.failures:
            self.failures -= 1
            raise OSError(10055, "buffer full")
        return len(data)

    def close(self):
        pass


class UdpLinkChecks(unittest.TestCase):
    def test_retries_transient_windows_send_buffer_exhaustion(self):
        sock = FakeSocket(failures=2)
        with patch("pc_fpga.ethernet.udp_link.socket.socket", return_value=sock), \
             patch("pc_fpga.ethernet.udp_link.sleep") as wait:
            link = UdpPeer(("0.0.0.0", 0))
            link.sendto(b"frame", ("192.168.1.10", 8080))

        self.assertEqual(sock.send_calls, 3)
        self.assertEqual([call.args[0] for call in wait.call_args_list], [0.001, 0.002])

    def test_stops_after_bounded_buffer_retries(self):
        sock = FakeSocket(failures=SEND_BUFFER_RETRIES + 1)
        with patch("pc_fpga.ethernet.udp_link.socket.socket", return_value=sock), \
             patch("pc_fpga.ethernet.udp_link.sleep"):
            link = UdpPeer(("0.0.0.0", 0))
            with self.assertRaisesRegex(OSError, r"sendto\(192\.168\.1\.10:8080\) failed"):
                link.sendto(b"frame", ("192.168.1.10", 8080))

        self.assertEqual(sock.send_calls, SEND_BUFFER_RETRIES + 1)


if __name__ == "__main__":
    unittest.main()
