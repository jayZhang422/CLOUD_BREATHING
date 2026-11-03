#!/usr/bin/env python3
"""Foreground-aware loss for the Task06 sparse tumour target."""
import torch
import torch.nn.functional as F


def loss_value(logits, target):
    """Return 0.5 voxel-balanced BCE + 0.5 batch-pooled foreground Dice."""
    logits, target = logits.float(), target.float()
    foreground = target > 0
    background = ~foreground
    has_foreground, has_background = foreground.any(), background.any()
    if has_foreground and has_background:
        bce = 0.5 * F.softplus(-logits[foreground]).mean()
        bce = bce + 0.5 * F.softplus(logits[background]).mean()
    elif has_foreground:
        bce = F.softplus(-logits).mean()
    else:
        bce = F.softplus(logits).mean()
    if has_foreground:
        probability = logits.sigmoid()
        dice = 1.0 - (2.0 * (probability * target).sum() + 1.0) / (
            probability.sum() + target.sum() + 1.0)
    else:
        dice = logits.sum() * 0.0
    return 0.5 * bce + 0.5 * dice


def selfcheck():
    logits = torch.zeros((2, 1, 512, 512), dtype=torch.float16, requires_grad=True)
    target = torch.zeros_like(logits)
    target[0, 0, 250:254, 250:254] = 1
    loss = loss_value(logits, target)
    assert loss.dtype == torch.float32 and torch.isfinite(loss)
    loss.backward()
    assert torch.isfinite(logits.grad).all()
    assert (logits.grad[target > 0] < 0).all()
    assert (logits.grad[target == 0] > 0).all()
    empty = torch.zeros((1, 1, 32, 32), dtype=torch.float16)
    assert loss_value(torch.full_like(empty, -2.0), empty) < loss_value(empty, empty)
    full = torch.ones_like(empty)
    full_logits = torch.zeros_like(empty, requires_grad=True)
    full_loss = loss_value(full_logits, full)
    assert torch.isfinite(full_loss)
    full_loss.backward()
    assert (full_logits.grad < 0).all()
    print('TASK06_LOSS_V3_SELFCHECK_PASS')


if __name__ == '__main__':
    selfcheck()
