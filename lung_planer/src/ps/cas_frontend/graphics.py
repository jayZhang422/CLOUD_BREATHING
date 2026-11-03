"""Choose the GLES surface format before Qt creates its first window."""
import os
from PySide6.QtCore import Qt, QCoreApplication
from PySide6.QtGui import QSurfaceFormat


def requested_scene_antialiasing():
    """SSAA avoids the unavailable multisample View3D FBO on the Mali ES2 path."""
    board = os.environ.get('CLOUD_BREATHING_KV260', '0').lower() in ('1', 'true', 'yes')
    mode = os.environ.get('CLOUD_BREATHING_SCENE_AA', 'ssaa' if board else 'msaa').lower()
    return mode if mode in ('none', 'msaa', 'ssaa') else ('ssaa' if board else 'msaa')


def requested_msaa_samples():
    """Request a supported quality level; the driver determines actual samples."""
    try:
        samples = int(os.environ.get('CLOUD_BREATHING_MSAA_SAMPLES',
                                     '2' if requested_scene_antialiasing() == 'msaa' else '0'))
    except ValueError:
        samples = 2
    return samples if samples in (0, 2, 4, 8) else 2


def configure_board_graphics():
    if os.environ.get('CLOUD_BREATHING_KV260', '0').lower() not in ('1', 'true', 'yes'):
        return
    # The previous standalone viewer requests an ES2 RGB8/depth16 config from
    # libMali. Request the same format here instead of Qt's desktop GL default.
    QCoreApplication.setAttribute(Qt.ApplicationAttribute.AA_UseOpenGLES)
    fmt = QSurfaceFormat()
    fmt.setRenderableType(QSurfaceFormat.RenderableType.OpenGLES)
    fmt.setVersion(2, 0)
    fmt.setProfile(QSurfaceFormat.OpenGLContextProfile.NoProfile)
    fmt.setRedBufferSize(8)
    fmt.setGreenBufferSize(8)
    fmt.setBlueBufferSize(8)
    fmt.setAlphaBufferSize(0)
    fmt.setDepthBufferSize(16)
    fmt.setStencilBufferSize(0)
    samples = requested_msaa_samples()
    fmt.setSamples(samples)
    QSurfaceFormat.setDefaultFormat(fmt)
    print(f'Qt surface request: OpenGL ES 2.0, RGB8, depth16, stencil0, samples{samples}', flush=True)
