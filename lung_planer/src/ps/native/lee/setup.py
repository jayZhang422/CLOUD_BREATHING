"""Build the experimental, instrumented Lee coordinator on the target board."""
from setuptools import Extension, setup

setup(
    name='centerline-lee-experiment',
    version='0.1',
    ext_modules=[Extension('_lee_native', ['lee_native.cpp'], language='c++',
                           extra_compile_args=['-O3', '-std=c++17'])],
)
