"""mkdc 部署参考：INT8 权重/特征、INT32 MAC、INT64 再量化、INT16 logits。

只在 ReLU6 后量化特征；DW 分支和残差在宽整数域合并后统一舍入。
使用 PyTorch 原生 fake-quant 做 QAT；整数推理不调用 fake-quant。
"""
import copy
import math

import torch
from torch import nn
from torch.nn import functional as F
from torch.nn.utils.fusion import fuse_conv_bn_eval


BLOCKS = ("e1", "e2", "e3", "mid", "d3", "d2", "d1")


def weight_quant(weight):
    scale = weight.detach().abs().flatten(1).amax(1).clamp_min(1e-12) / 127
    quant = torch.round(weight.detach() / scale[:, None, None, None]).clamp(-127, 127)
    return quant.to(torch.int8), scale


def round_even_shift(value, shift):
    """有符号整数右移，最近偶数舍入；调用方保证 abs(value) < 2**62。"""
    if shift == 0:
        return value
    magnitude = value.abs()
    whole = magnitude >> shift
    remainder = magnitude & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    increment = (remainder > half) | ((remainder == half) & ((whole & 1) != 0))
    return (whole + increment.to(torch.int64)) * value.sign()


def integer_mac(x, weight, groups, padding):
    """受证明上界约束的精确整数 MAC；FP32 仅作为 CUDA 卷积运算载体。

    每个乘积和所有部分和的绝对值均小于 2**24；禁止 TF32/AMP。
    偏置和缩放单独用 INT64 计算，并由独立 INT64 卷积自检核对。
    """
    terms = weight.shape[1] * weight.shape[2] * weight.shape[3]
    if terms * 128 * 127 >= 2**24:
        raise ValueError("MAC exceeds exact FP32 integer range")
    return F.conv2d(x.float(), weight.float(), None, padding=padding, groups=groups).to(torch.int64)


class DeploymentNet(nn.Module):
    def __init__(self, original):
        super().__init__()
        original = copy.deepcopy(original).eval()
        self.convs = nn.ModuleDict()
        self.identity_skip = {}
        self.scales = {"input": 1.0}
        self.observed = {}
        self.mode = "float"
        self.capture = None
        self.packed = {}
        self.merges = {}
        for name in BLOCKS:
            block = getattr(original, name)
            self.put(name + ".expand", fuse_conv_bn_eval(block.expand[0], block.expand[1]))
            channels = block.k3.out_channels
            permutation = torch.arange(channels).reshape(2, channels // 2).T.flatten()
            inverse = torch.argsort(permutation)
            bn = block.project[0]
            alpha = (bn.weight / torch.sqrt(bn.running_var + bn.eps))[inverse]
            beta = (bn.bias - bn.running_mean * bn.weight / torch.sqrt(bn.running_var + bn.eps))[inverse]
            for suffix, source, bias in (("dw3", block.k3, beta), ("dw5", block.k5, torch.zeros_like(beta))):
                conv = copy.deepcopy(source)
                conv.weight = nn.Parameter(source.weight.detach() * alpha[:, None, None, None])
                conv.bias = nn.Parameter(bias.detach().clone())
                self.put(name + "." + suffix, conv)
            project = fuse_conv_bn_eval(block.project[2], block.project[3])
            project.weight = nn.Parameter(project.weight.detach()[:, inverse].clone())
            self.put(name + ".project", project)
            self.identity_skip[name] = isinstance(block.skip, nn.Identity)
            if not self.identity_skip[name]:
                self.put(name + ".skip", fuse_conv_bn_eval(block.skip[0], block.skip[1]))
        self.put("head", copy.deepcopy(original.head))

    def put(self, name, conv):
        self.convs[name.replace(".", "__")] = conv

    def conv(self, name):
        return self.convs[name.replace(".", "__")]

    def activation(self, name, value, relu=True):
        if relu:
            value = F.relu6(value)
        if self.mode == "calibrate":
            maximum = float(value.detach().abs().amax())
            self.observed[name] = max(self.observed.get(name, 0.0), maximum)
        if self.mode == "fake":
            bits = 16 if name == "head" else 8
            value = torch.fake_quantize_per_tensor_affine(value, self.scales[name], 0,
                                                          -(1 << (bits - 1)), (1 << (bits - 1)) - 1)
        return value

    def float_conv(self, name, value):
        conv = self.conv(name)
        weight = conv.weight
        if self.mode == "fake":
            _, scale = weight_quant(weight)
            weight = torch.fake_quantize_per_channel_affine(weight, scale,
                torch.zeros_like(scale, dtype=torch.int32), 0, -127, 127)
        return F.conv2d(value, weight, conv.bias, padding=conv.padding, groups=conv.groups)

    def finish_calibration(self):
        if len(self.observed) != 22:
            raise RuntimeError("Missing activation calibration nodes")
        self.scales.update({name: max(maximum, 1e-8) / (32767 if name == "head" else 127)
                            for name, maximum in self.observed.items()})

    def prepare_integer(self):
        self.packed = {}
        self.merges = {}
        for name in [key.replace("__", ".") for key in self.convs]:
            conv = self.conv(name)
            # 参数只在 CPU 生成一次；禁止 CPU/CUDA 分别重算浮点 scale。
            weight, scale = weight_quant(conv.weight.detach().cpu())
            bound = weight.long().abs().flatten(1).sum(1) * 128
            self.packed[name] = {"weight": weight.to(conv.weight.device), "scale": scale.double(),
                                 "bias": conv.bias.detach().cpu().double(), "bound": bound,
                                 "groups": conv.groups, "padding": conv.padding[0]}

    def accumulate(self, name, value, input_scale):
        packed = self.packed[name]
        accumulator = integer_mac(value, packed["weight"], packed["groups"], packed["padding"])
        if self.capture is not None:
            self.capture[name + ".mac"] = accumulator.detach().cpu().to(torch.int32)
        return accumulator, packed["scale"] * input_scale, packed["bias"], packed["bound"]

    def merge(self, name, parts, output_scale, relu=True, bits=8):
        """同一宽域合并全部分支与偏置，最终只舍入一次；不提前 INT8 饱和。"""
        if name not in self.merges:
            device = parts[0][0].device
            ratios = [part[1].detach().cpu().double() / output_scale for part in parts]
            bias_ratio = sum(part[2].detach().cpu().double() for part in parts) / output_scale
            maximum = max(float(r.abs().max()) for r in ratios)
            bound = sum(part[3].detach().cpu().double() * ratio.abs() for part, ratio in zip(parts, ratios)) + bias_ratio.abs()
            shift = min(24, math.floor(math.log2((2**30 - 1) / max(maximum, 1e-30))),
                        math.floor(math.log2((2**61 - 1) / max(float(bound.max()), 1e-30))))
            if shift < 0:
                raise OverflowError("No safe fixed-point multiplier for " + name)
            self.merges[name] = {"shift": shift,
                "multipliers": [torch.round(r * 2**shift).long().to(device) for r in ratios],
                "bias_fixed": torch.round(bias_ratio * 2**shift).long().to(device),
                "output_scale": output_scale, "bits": bits, "relu6": relu,
                "numerator_abs_bound": float(bound.max()) * 2**shift}
        config = self.merges[name]
        numerator = config["bias_fixed"][None, :, None, None]
        for part, multiplier in zip(parts, config["multipliers"]):
            numerator = numerator + part[0] * multiplier[None, :, None, None]
        result = round_even_shift(numerator, config["shift"])
        lower = 0 if relu else -(1 << (bits - 1))
        upper = min((1 << (bits - 1)) - 1, round(6 / output_scale)) if relu else (1 << (bits - 1)) - 1
        result = result.clamp(lower, upper)
        if self.capture is not None:
            self.capture[name] = result.detach().cpu().to(torch.int16 if bits == 16 else torch.int8)
        return result

    def block(self, name, x, input_scale):
        if self.mode != "integer":
            expanded = self.activation(name + ".expand", self.float_conv(name + ".expand", x))
            mixed = self.activation(name + ".mix", self.float_conv(name + ".dw3", expanded)
                                    + self.float_conv(name + ".dw5", expanded))
            skip = x if self.identity_skip[name] else self.float_conv(name + ".skip", x)
            return self.activation(name + ".out", self.float_conv(name + ".project", mixed) + skip)
        expanded = self.merge(name + ".expand", [self.accumulate(name + ".expand", x, input_scale)],
                              self.scales[name + ".expand"])
        mixed = self.merge(name + ".mix", [self.accumulate(name + suffix, expanded, self.scales[name + ".expand"])
                                            for suffix in (".dw3", ".dw5")], self.scales[name + ".mix"])
        project = self.accumulate(name + ".project", mixed, self.scales[name + ".mix"])
        if self.identity_skip[name]:
            channels = x.shape[1]
            scale = torch.full((channels,), input_scale, dtype=torch.float64, device=x.device)
            skip = x, scale, torch.zeros_like(scale), torch.full_like(scale, 128)
        else:
            skip = self.accumulate(name + ".skip", x, input_scale)
        return self.merge(name + ".out", [project, skip], self.scales[name + ".out"])

    def join(self, name, x, x_scale, skip, skip_scale):
        scale = max(x_scale, skip_scale)
        if self.mode == "integer":
            aligned = []
            for suffix, value, source_scale in (("up", x, x_scale), ("skip", skip, skip_scale)):
                channels = value.shape[1]
                s = torch.full((channels,), source_scale, dtype=torch.float64, device=value.device)
                aligned.append(self.merge(name + ".concat_" + suffix,
                    [(value, s, torch.zeros_like(s), torch.full_like(s, 128))], scale, relu=False))
            return torch.cat(aligned, 1), scale
        if self.mode == "fake":
            x = torch.fake_quantize_per_tensor_affine(x, scale, 0, -128, 127)
            skip = torch.fake_quantize_per_tensor_affine(skip, scale, 0, -128, 127)
        return torch.cat((x, skip), 1), scale

    def forward(self, x):
        if self.mode == "integer":
            x = x.to(torch.int64)
        e1 = self.block("e1", x, 1.0)
        pool = lambda value: F.max_pool2d(value.float(), 2).long() if self.mode == "integer" else F.max_pool2d(value, 2)
        e2 = self.block("e2", pool(e1), self.scales.get("e1.out", 1.0))
        e3 = self.block("e3", pool(e2), self.scales.get("e2.out", 1.0))
        y = self.block("mid", pool(e3), self.scales.get("e3.out", 1.0))
        previous = "mid"
        for name, skip, skip_name in (("d3", e3, "e3"), ("d2", e2, "e2"), ("d1", e1, "e1")):
            y = F.interpolate(y.float(), size=skip.shape[-2:], mode="nearest")
            if self.mode == "integer":
                y = y.long()
            y, scale = self.join(name, y, self.scales.get(previous + ".out", 1.0),
                                 skip, self.scales.get(skip_name + ".out", 1.0))
            y = self.block(name, y, scale)
            previous = name
        if self.mode == "integer":
            return self.merge("head", [self.accumulate("head", y, self.scales["d1.out"])],
                               self.scales["head"], relu=False, bits=16)
        return self.activation("head", self.float_conv("head", y), relu=False)

    def dequantized(self, x):
        output = self(x)
        return output.float() * self.scales["head"] if self.mode == "integer" else output


def selfcheck(device):
    # 与 Python 任意精度整数独立比对正负 tie，覆盖舍入与整数范围边界。
    checks = 0
    for shift in range(1, 25):
        half = 1 << (shift - 1)
        values = [n * (1 << shift) + delta for n in range(-8, 9)
                  for delta in (-half - 1, -half, -half + 1, 0, half - 1, half, half + 1)]
        actual = round_even_shift(torch.tensor(values, device=device, dtype=torch.int64), shift).cpu().tolist()
        expected = []
        for value in values:
            whole, remainder = divmod(abs(value), 1 << shift)
            whole += int(remainder > half or (remainder == half and whole % 2))
            expected.append(whole if value >= 0 else -whole)
        assert actual == expected, (shift, actual, expected)
        checks += len(values)
    generator = torch.Generator().manual_seed(20261011)
    for channels, outputs, kernel, groups in ((3, 16, 1, 1), (192, 64, 1, 1), (16, 16, 3, 16), (16, 16, 5, 16)):
        x = torch.randint(-128, 128, (1, channels, 9, 11), generator=generator, dtype=torch.int64)
        weight = torch.randint(-127, 128, (outputs, channels // groups, kernel, kernel), generator=generator, dtype=torch.int64)
        padded = F.pad(x, (kernel // 2,) * 4)
        windows = padded.unfold(2, kernel, 1).unfold(3, kernel, 1)
        expected = torch.zeros((1, outputs, 9, 11), dtype=torch.int64)
        for output in range(outputs):
            group = output // (outputs // groups)
            source = windows[:, group * (channels // groups):(group + 1) * (channels // groups)]
            expected[:, output] = (source * weight[output][None, :, None, None]).sum((1, 4, 5))
        actual = integer_mac(x.to(device), weight.to(device), groups, kernel // 2).cpu()
        assert torch.equal(actual, expected), (channels, kernel)
        checks += actual.numel()
    return {"status": "PASS", "independent_integer_checks": checks,
            "cuda_mac": "FP32 exact integer carrier; TF32 and AMP disabled; <2**24 proof enforced"}
