# MoonEXR 十一月功能扩展

渲染与科学成像文件同时携带 HDR 颜色、深度、法线、强度和对象标识，普通预览图无法保留其名字、类型、坐标和精确位。项目为 MoonBit 应用提供真实 EXR 交换与区域访问，并增加可用于质量门禁的样本核验和掩膜统计，不依赖 C++ 图像运行时。

## 1. 位级样本差异与数值误差

`Plane::compare_samples`：同窗口和同类型平面比较样本原始位，报告差异数和有限值对最大绝对误差。可区分 UINT32 精度差异、正负零和 NaN payload；忽略通道名字，便于显式重命名后的对照。

复杂度与代价：线性 O(P) 时间、O(1) 额外空间；不比较 metadata、颜色外观或结构字节，不做自动容差判定。

## 2. 对象掩膜下的有限值统计

`Plane::masked_statistics`：用同窗口 UINT32 的非零 mask 选择像素，分别统计选中、有限和非有限数，返回 min/max/mean；背景、未选中和 NaN/Infinity 不混淆。

复杂度与代价：O(P) 时间、O(1) 额外空间；加权在线均值避免相反极值差值溢出，无有效值时返回 None。

## 运行

```sh
moon run examples/november --target native --deny-warn
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
```

Windows当前工具链路径问题沿用README的项目适配脚本；源代码临时命名空间尚未发布。

## 范围

不实现 tiled、deep、multipart、PIZ/DWA 等额外codec、渲染器或 ICC 色彩管理；当前完整输入在内存。质量比较只处理匹配的窗口和像素类型，不自动重采样。

官方 OpenEXR 双向位/窗口/元数据互操作；新增样本差异与掩膜统计测试。 具体当前执行结果由本地检查记录提供，不以CI配置代替远端成功记录。
