"""Parameterized 2.5D ResUNet with the project's mkdc/ReLU6 blocks."""
from __future__ import annotations

import torch
from torch import nn
from torch.nn import functional as F


class MKDCBlock(nn.Module):
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.expand = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
        )
        self.k3 = nn.Conv2d(out_ch, out_ch, 3, padding=1, groups=out_ch, bias=False)
        self.k5 = nn.Conv2d(out_ch, out_ch, 5, padding=2, groups=out_ch, bias=False)
        self.project = nn.Sequential(
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
            nn.Conv2d(out_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
        )
        self.skip = nn.Identity() if in_ch == out_ch else nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.expand(x)
        y = self.k3(y) + self.k5(y)
        b, c, h, w = y.shape
        if c % 2:
            raise RuntimeError("mkdc channel shuffle requires an even channel count")
        y = y.reshape(b, 2, c // 2, h, w).transpose(1, 2).reshape(b, c, h, w)
        return F.relu6(self.project(y) + self.skip(x), inplace=True)


class ResUNet(nn.Module):
    def __init__(self, out_channels: int = 1, base: int = 16):
        super().__init__()
        c = [base, base * 2, base * 4, base * 8]
        self.e1, self.e2, self.e3, self.mid = (
            MKDCBlock(3, c[0]), MKDCBlock(c[0], c[1]),
            MKDCBlock(c[1], c[2]), MKDCBlock(c[2], c[3])
        )
        self.pool = nn.MaxPool2d(2)
        self.d3, self.d2, self.d1 = (
            MKDCBlock(c[3] + c[2], c[2]),
            MKDCBlock(c[2] + c[1], c[1]),
            MKDCBlock(c[1] + c[0], c[0]),
        )
        self.head = nn.Conv2d(c[0], out_channels, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        e1 = self.e1(x)
        e2 = self.e2(self.pool(e1))
        e3 = self.e3(self.pool(e2))
        y = self.mid(self.pool(e3))
        y = self.d3(torch.cat((F.interpolate(y, size=e3.shape[-2:], mode="nearest"), e3), 1))
        y = self.d2(torch.cat((F.interpolate(y, size=e2.shape[-2:], mode="nearest"), e2), 1))
        y = self.d1(torch.cat((F.interpolate(y, size=e1.shape[-2:], mode="nearest"), e1), 1))
        return self.head(y)
