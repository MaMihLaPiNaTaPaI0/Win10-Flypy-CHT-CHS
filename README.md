# Win10-Flypy-CHT-CHS
WIN10 个人使用 微软拼音双拼掛接方案 台湾繁體 備份，如需使用請自行更換檔案路徑

【系统与输入法环境档案】

1. **基础环境**：
   - 操作系统：Windows 10（台湾繁体语言环境，默认控制台代码页为 Big5，PowerShell 脚本必须使用纯英文字符或保存为 UTF-8-BOM 以防路径乱码）。
   - 输入法方案：微软拼音（已开启“使用以前版本的微软拼音”兼容模式 + 挂载小鹤双拼注册表 + 关闭动态排名 `Enable Dynamic Candidate Ranking=0` + 开启自定义短语 `Enable EUDP=1`）。

2. **核心文件与路径规范**：
   - 本地工具与词库仓库：`D:\PinyinTool\`
   - 原始简体词库备份：`D:\PinyinTool\original_backup.lex`
   - 精修台湾正体习惯用语词库源文本：`D:\PinyinTool\clean_cht.txt`（编码 UTF-8，格式为 `编码,位置=词条`，如 `rrjm,1=軟體`、`vhf,1=指揮`）。
   - 编译生成的台湾正体二进制词库：`D:\PinyinTool\flypy_cht.lex`
   - 系统生效唯一目标路径：`%AppData%\Microsoft\InputMethod\Chs\ChsPinyinEUDPv1.lex`
   - 桌面一键切换快捷方式：`Flypy_CHS.lnk`（调用 `D:\PinyinTool\switch_chs.ps1`，复制 `original_backup.lex` 并设 `OutputCharSet=0`）与 `Flypy_CHT.lnk`（调用 `D:\PinyinTool\switch_cht.ps1`，复制 `flypy_cht.lex` 并设 `OutputCharSet=1`）。

3. **关键底层技术规范（已验证踩坑避雷）**：
   - **禁止使用深蓝词库转换或 `PinyinLexTool.exe` 导入**：深蓝转换全量库会报错，且 `PinyinLexTool` 会拦截以 `u` 或 `v` 开头的小鹤双拼编码（如 `vhf`、`uesu`），同时不要点开微软拼音UWP设置的“用户定义词库”界面（加载 6.8 万行必卡死）。
   - **专属 `.lex` 二进制结构（64字节文件头 + 16字节单条记录头）**：
     - 文件头：`mschxudp` + `uint32(0x00600002)` + `uint32(1)` + `uint32(64)`（索引偏移）+ `uint32(dataOffset)` + `uint32(totalSize)` + `uint32(count)`（第28字节为词条总数）+ `uint32(timestamp)` + 28字节0。
     - 单条记录头（16字节）：`uint16(16)` + `uint16(16)` + `uint16(16 + codeBytes.Length)` + `byte(pos)` + `byte(6)` + `uint64(0)`，后接 UTF-16LE 编码（带 `\0`）与汉字（带 `\0`），且所有记录必须按 `Code, Pos` 升序排列。
   - **脚本语法避坑**：在 PowerShell 中解析文本行时，避免使用正则 `$matches` 索引下标，统一使用 `IndexOf` 与 `Substring` 解析。切换词库需先结束 `ChsIME` 与 `ctfmon` 进程，覆盖后重启 `ctfmon.exe`，并通过按两次 `Win + Space` 刷新内存缓存。
