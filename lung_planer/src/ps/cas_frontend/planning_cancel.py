"""Cooperative per-job cancellation; never interrupt an in-flight DMA call."""
from contextlib import contextmanager
from threading import local

_state = local()


class PlanningCancelled(RuntimeError):
    pass


def checkpoint():
    token = getattr(_state, 'token', None)
    if token is not None and token.is_set():
        raise PlanningCancelled('规划已停止')


@contextmanager
def cancellation_scope(token):
    previous = getattr(_state, 'token', None)
    _state.token = token
    try:
        checkpoint()
        yield
    finally:
        _state.token = previous


def cancellable_job(method):
    def run(worker, job):
        try:
            with cancellation_scope(job.get('_cancel_token')):
                method(worker, job)
        except PlanningCancelled:
            worker.cancelled.emit(job['revision'])
    return run
