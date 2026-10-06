# Mesh Rendering Example

Renders a 3D scene via a first person camera. Use the D-pad to rotate and move the camera, L1/R1 to strafe.

This is the most complex example so far, utilizing many technologies:

- Buffered, Z-ordered rendering
- GTE vertex transformation
- Texture management
- Mesh management
- Fast fixed-point trigonometry using a pre-calculated sine table
- Matrix math
- Gamepad input
- First person camera logic.

Use `build.bat` to compile `iso/PSX.EXE`.

Use `build_iso.bat` to build a CD-ROM image (requires [mkpsxiso by Lameguy64](https://github.com/lameguy64/mkpsxiso)).
