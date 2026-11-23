# Optional YOLOv8n model

SafePath starts with Apple's built-in Vision rectangle detector and does not need a custom model.

To try a compatible YOLOv8n Core ML object-detection model:

1. Export or obtain a Core ML package with an object-detection output compatible with `VNCoreMLRequest`.
2. Name it `YOLOv8n.mlpackage`.
3. Put it at `SafePath/SafePath/Sources/Detection/Resources/YOLOv8n.mlpackage` and include the package in the XcodeGen target sources.
4. Regenerate the project with `xcodegen generate` and build on macOS.

The app looks for `YOLOv8n.mlmodelc` first and compiles a bundled `YOLOv8n.mlpackage` when needed. Core ML output labels and box conventions vary by export; validate the model on the target iPhone before using it. Vision's rectangle fallback reports `Possible obstacle`, not a semantic object class.
