# MoonEXR

MoonBit 原生 OpenEXR 高动态范围多通道图像交换库，当前本地开发中。
本地命名空间 `local/moonexr` 为私有暂存；账号确定前不发布。
目标为单部件平面扫描线、HALF/FLOAT/UINT、NONE/RLE/ZIPS/ZIP。

用途：渲染素材交换、科学成像记录、Web/Wasm 离线处理。
不实现 deep、多部件、tiled、图像渲染或完整色彩管理。

Windows 可使用 `tools/windows/moon.ps1` 适配现有工具链的路径问题。
其他平台使用标准 `moon check`、`moon build`、`moon test`。
