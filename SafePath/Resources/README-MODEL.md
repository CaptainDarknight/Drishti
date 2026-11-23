# Optional YOLOv8n model

Drishti starts with Apple's built-in Vision rectangle proposals and classifies detected regions with Vision's on-device image classifier. It needs no API key or network connection. Region classification is not a complete object detector and can miss objects or assign an incorrect label.

To try a compatible YOLOv8n Core ML object-detection model:

1. Export or obtain a Core ML package with an object-detection output compatible with `VNCoreMLRequest`.
2. Name it `YOLOv8n.mlpackage`.
3. Put it at `SafePath/SafePath/Sources/Detection/Resources/YOLOv8n.mlpackage` and include the package in the XcodeGen target sources.
4. Regenerate the project with `xcodegen generate` and build on macOS.

The app looks for `YOLOv8n.mlmodelc` first and compiles a bundled `YOLOv8n.mlpackage` when needed. Core ML output labels and box conventions vary by export; validate the model on the target iPhone before using it. Without a compatible model, labels may be generic or wrong; never treat detections as guaranteed safety coverage.
