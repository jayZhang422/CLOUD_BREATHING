"""Interactive STL preview: drag to rotate, wheel to zoom, keys 1-9 toggle objects, L toggles lobe opacity."""

import argparse
from pathlib import Path

import vtkmodules.vtkRenderingFreeType
from vtkmodules.vtkRenderingCore import vtkRenderer, vtkRenderWindow, vtkRenderWindowInteractor, vtkTextActor
from vtkmodules.vtkInteractionStyle import vtkInteractorStyleTrackballCamera
from .chest_ct_to_stl import ROOT, LOBE_NAMES, NAMES, scene_actors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "stl_vessels_refined/01")
    args = parser.parse_args()
    actors = scene_actors(args.output_dir)
    if not actors:
        raise ValueError("No exported STLs found; run main.py convert first")
    renderer = vtkRenderer()
    renderer.SetUseOIT(False)
    renderer.SetBackground(.96, .97, .99)
    for name, actor in actors.items():
        if name in LOBE_NAMES:
            actor.GetProperty().SetOpacity(.15)
        renderer.AddActor(actor)
    label = vtkTextActor()
    label.SetInput("\n".join(f"{i + 1}: {name}" for i, name in enumerate(NAMES)) +
                   "\nL: transparent / solid lobes\nDrag: rotate   Wheel: zoom   R: reset")
    label.SetPosition(18, 18)
    label.GetTextProperty().SetColor(.12, .15, .19)
    label.GetTextProperty().SetFontSize(18)
    renderer.AddViewProp(label)
    window = vtkRenderWindow()
    window.SetWindowName("CT - own mkdc model predictions")
    window.SetSize(1400, 1000)
    window.AddRenderer(renderer)
    interactor = vtkRenderWindowInteractor()
    interactor.SetRenderWindow(window)
    interactor.SetInteractorStyle(vtkInteractorStyleTrackballCamera())

    def keypress(caller, event):
        key = caller.GetKeySym().lower()
        if key in "123456789" and len(key) == 1:
            actor = actors.get(NAMES[int(key) - 1])
            if actor is not None:
                actor.SetVisibility(not actor.GetVisibility())
        elif key == "l":
            for name in LOBE_NAMES:
                if name in actors:
                    prop = actors[name].GetProperty()
                    prop.SetOpacity(1. if prop.GetOpacity() < .5 else .15)
        elif key == "r":
            renderer.ResetCamera()
        window.Render()

    interactor.AddObserver("KeyPressEvent", keypress)
    renderer.ResetCamera()
    camera = renderer.GetActiveCamera()
    center = camera.GetFocalPoint()
    camera.SetPosition(center[0] + 90, center[1] - 800, center[2] + 40)
    camera.SetViewUp(0, 0, 1)
    renderer.ResetCameraClippingRange()
    window.Render()
    interactor.Initialize()
    interactor.Start()


if __name__ == "__main__":
    main()
