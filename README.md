# MoonEXR

MoonBit 原生的 OpenEXR 高动态范围、多通道图像交换与区域访问库。native、JavaScript、Wasm、Wasm-GC 共用一套格式、压缩和样本逻辑；运行时不绑定 OpenEXR C++ 或 Python。

当前为本地预发布：`local/moonexr`、`private = true`、无公开远程仓库。账号确定后才配置真实模块名和公开安装地址；现在不要执行 `moon add local/moonexr`。

## 生态价值与场景

EXR 通道可以保存颜色，也可以保存深度、法线、传感器强度、对象 ID 等数值。普通 PNG/JPEG 或 Radiance HDR 的数据模型不能替代有名字、有类型、带窗口和元数据的 EXR 通道交换。

- 渲染与内容工具：交换多个命名 render pass，只选 beauty 层和所需区域生成预览，同时保留 HDR 和深度原值，输出仍可被官方 OpenEXR 读取。
- 科学成像与采集：分批写入浮点测量及准确的 UINT32 样本 ID，保存采集说明/单位，按块分析有限值、直方图和异常值；不借图像预览隐式截断原数据。
- Web/Wasm 离线工具：在原生 MoonBit 代码中检查文件、选择区域/通道并输出诊断 RGBA8，供上层 Canvas 或分析 UI 使用，无需嵌入 C++ 色彩/图像运行时。

`examples/render_assets`、`scientific_imaging`、`offline_preview` 分别包含完整可运行断言。它与 HDF5 多维数组、ORC 表记录、SDMX 统计语义或 ICC 色彩管理的核心不同。邻近图像库仍有价值；本项目补充的是实际 OpenEXR 互操作，不宣称重做全部图像生态，也不能证明所有生态代码绝无相似实现。

## 安装与复现

使用 [官方 MoonBit 工具链](https://docs.moonbitlang.com/en/latest/download-and-install.html)；本机验证版本 `moonc 0.10.16`，高于赛事要求0.10.14。固定依赖见 `moon.mod`。

```sh
moon version --all
moon check --target all --deny-warn
moon build --target all --deny-warn
moon test --target all --deny-warn
moon run examples/render_assets
moon run examples/scientific_imaging
moon run examples/offline_preview --target js
moon run examples/scale --target native --release
```

本地工程包导入 `"local/moonexr" @exr`，示例目录已配置，可直接运行。公开依赖安装说明将随真实账号发布补齐。

Windows 的 Moon20261016 OCaml 子工具可能不接受驱动传入的 `\\?\` 长路径；可用随项目的进程参数适配器（首次构建需要 MSVC Build Tools）：

```powershell
.\tools\windows\moon.ps1 check --target all --deny-warn
.\tools\windows\moon.ps1 test --target all --deny-warn
.\tools\windows\moon.ps1 run examples/render_assets
```

适配器只生成 `_build` 内容，保留官方编译器，不修改全局环境；其他平台直接使用标准 `moon`。

## 最小示例

```moonbit
fn main raise {
  let w = @exr.Window::new(-1, 2, 1, 3)
  let ids = @exr.Plane::from_values(
    { name: "id", kind: U32, linear: true }, w,
    [0.0, 1.0, 16777217.0, 4294967295.0, 42.0, 7.0],
  )
  let image = @exr.Image::new(w, [ids])
  let file = @exr.ExrFile::open(@exr.encode(image))
  let roi = file.read(region=Some(@exr.Window::new(0, 2, 1, 3)))
  assert_eq(roi.plane("id").bits_at(1, 2), 16777217U)
}
```

窗口是包含两端的绝对图像坐标。区域请求与 dataWindow 相交后裁剪；完全不相交会报错。displayWindow 保留原画布，不随 crop 缩小。通道按 UTF-8 字节顺序规范排列，接口返回的目录/元数据数组是副本。

## 格式兼容边界

| 项目 | 已支持 | 明确不支持/不承诺 |
| --- | --- | --- |
| 存储 | EXR version2单部件、平面scanline；增序/减序声明与offset表读取 | tiled、deep、multipart、随机行序声明、未来flags |
| 通道 | UINT32、IEEE HALF16、FLOAT32，单位采样，命名层、长UTF-8名字 | 子采样、自动合成Y/RY/BY、任意像素类型 |
| 压缩 | NONE、RLE、ZIPS、ZIP及无收益raw fallback；ZIP16行尾块 | PIZ、PXR24、B44、DWAA/DWAB等；没有隐式降级 |
| 元数据 | 标准窗口/屏幕/像素比例，未知可选属性原始保留；string/int/float/chromaticities辅助接口 | 任意可选属性的领域解释、ICC变换、设备校准 |
| 读写 | 确定性whole-image编码，原子批push，块计划、区域/通道选择、分批返回 | 文件IO流式读取、零复制、物理字节完全一致重写 |
| 处理 | crop/select/rename/translate、层选择/合并、显式类型转换、有限值统计/直方图、RGBA预览 | 合成器、滤镜引擎、渲染器、完整色彩管理 |

原始 `Plane::from_bits/sample_bits/bits_at` 路径不经过数值算术，保持 UINT32、NaN payload、正负零、Infinity。`from_values` 和 `map_values` 是数值路径，浮点转类型可能舍入/溢出；HALF数值输入先转换为Float32再按最近偶数舍入。UINT数值输入/转换必须是0..2^32-1内整数，拒绝分数/非有限值，不自动饱和。

`convert` 同类型保持全部位；HALF↔FLOAT通过位操作转换，窄化只保留高payload位。UINT→FLOAT可能失去整数精度，必须由调用方显式请求。`linear` 对应EXR pLinear编码提示，不代表通道已做色彩变换。

未知可选属性按名称/类型/原始payload保留；编码会重建结构、排序元数据并选择压缩，所以保留支持范围内的样本位和属性语义，不承诺原始header排列、压缩字节或物理chunk顺序。重写输出统一增序。文件入口/目录在open校验，压缩内容在读取选中块时校验；不会替调用方检查未选中的坏块。

## 扫描与增量写入

`ExrFile::scan(region=...,channels=...,batch_rows=...)` 按绝对y增序返回 Image，最多 `batch_rows` 行。当前块只解压一次；错误后scanner永久失败，重试不会跳过坏数据。`read_with_stats` 返回本次块数和逻辑解码字节；`plan` 返回精确编码块范围。

EXR压缩块将通道混合压缩，因此选择少量通道可以减少保留输出，**不会免去解压所选块中的其他通道**。区域可以跳过无交集块；完整输入Bytes仍在内存，plan本身不是远程range下载器。扫描返回批量不等于峰值工作内存只占这一批。

`Writer::new(window,channels,metadata=...)` 固定全局头；`push` 接受下一个全宽、连续、相同通道集合的行批次。批次不得含可选元数据，防止隐式丢弃。writer只取批次样本，display/screen等全局几何由构造器定义为默认屏幕设置和指定display。不支持借push改变header。失败push保留此前状态；未收到全部行时finish可重试，成功后关闭并释放保留输出。它保留压缩结果及最多一个未满块，不写磁盘。

## 预览与统计

`preview_rgba` 明确选择RGB/alpha名字、曝光、Clamp/Reinhard和gamma。输入应已处于调用方要求的线性色彩空间；此诊断预览不解析chromaticities做变换，不声称精确显示校准。premultiplied_alpha=true会在alpha>0时除以alpha，零alpha颜色输出0；未设置则直接映射颜色。NaN/非正值映射0，正Infinity映射1，alpha夹到0..1。原始平面始终保留。

统计分别报告NaN、正负Infinity、负零，有限值使用Welford算法求总体方差。没有有限样本时mean/min/max/variance为None；浮点溢出时不伪造有限结果。直方图含两端点，范围外和非有限值单独计数。

## CLI 与独立互操作

```sh
moon run cmd/main --target native -- inspect INPUT.exr
moon run cmd/main --target native -- bits INPUT.exr
moon run cmd/main --target native -- demo NEW.exr
moon run cmd/main --target native -- rewrite INPUT.exr NEW.exr zip
python -m venv _local/venv
# 激活环境后安装；Windows也可直接使用_local/venv/Scripts/python.exe
python -m pip install -r scripts/requirements-interop.txt
moon build --target native --deny-warn
python scripts/interop.py verify _build/native/debug/build/cmd/main/main.exe
```

CLI写入使用CreateNew，拒绝覆盖已有文件；bits输出原始unsigned位数组，限100万样本，只作小文件检查。rewrite先完整读入图像再编码。Python环境仅供开发验证，官方OpenEXR3.4.2和numpy2.3.4不是核心运行依赖。

独立oracle比较官方写出→MoonEXR读取、四种MoonEXR写出→官方读取的全部通道位、窗口/屏幕设置、元数据和拒绝覆盖行为。原始synthetic fixtures含负origin、UINT边界、NaN/Infinity/负零、ZIP尾块和减序文件；tiled用于明确拒绝。生成fixture字节不计有效代码量。

## 工程验证与资源边界

已配置GitHub Actions的四后端check/build/test、fmt/API一致性、三个场景、规模负载、官方互操作和本地打包卫生检查。远程成功记录须推送后才能确认；本地通过不等于正式赛事验收通过。

默认上限：文件256MiB、header1MiB、像素16,777,216、通道64、属性1024、chunk65,536、逻辑解码256MiB。文件/长度乘加和窗口维度受检；重复属性/通道、重叠chunk、错误解压长度、Adler32、缺失字段和不支持模式明确拒绝。Limits不是进程精确峰值内存；输入、压缩块、临时数组、防御性复制和输出会同时存在，不适合无额外隔离地接收任意规模不可信内容。

若C为chunk数、B为处理字节、N为保留样本，打开文件目录约O(C log C)（排序检查重叠）；区域plan按规则行号计算为O(1+命中块数)，不逐块遍历。解码、编码、类型转换、预览与统计约O(B+N)，通道排序/元数据排序另有O(K log K)。scanner缓存当前块，防止小批返回导致反复解压。writer原子push需要暂存该push生成的编码结果。代码未承诺并发安全；为每个并发任务使用独立scanner/writer。

`examples/scale` 验证98,304像素24块、区域4096像素只解码1块。它是可复现正确性负载，没有与OpenEXR的速度比较结论。

## 许可证与维护

Apache-2.0，见 LICENSE、NOTICE、THIRD_PARTY.md。依据 [OpenEXR官方格式](https://openexr.com/en/latest/OpenEXRFileLayout.html) 独立实现；测试对照使用 [官方Python API](https://openexr.com/en/latest/python.html)。AI辅助设计与开发；独立测试不替代对生产文件变体的兼容评估。

术语见CONTEXT.md，重要边界见docs/adr，公共接口见pkg.generated.mbti。扩展codec、tiled或multipart之前应增加独立生产者fixture及明确的数据模型。申报书、审查/AI/汇总报告只保存在 `_local` 或仓库外，通过gitignore及打包检查排除。
