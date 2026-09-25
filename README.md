# install-arch

裸机 Arch Linux 的一站式安装入口：把 [configs](https://github.com/jwu/configs)、
[desktop-settings](https://github.com/jwu/desktop-settings)、
[pi-config](https://github.com/jwu/pi-config) 三个仓库同步到 `~/bin` 下，再按顺序跑它们的安装脚本。

它解决的是「跑完 `configs/linux/install.sh`，结果 Waybar 的 niri-windows 模块、中文输入法、
乃至一批配置都不见了」这类问题：那三个安装脚本各自 `set -e`、遇错即停，裸机上 GitHub 一不通，
Waybar 模块构建失败就会把整个脚本打死，排在它后面的 `config.sh` 一行都不跑。本仓库把安装
拆成互相独立、失败不阻断的步骤，最后集中报告漏了哪些东西。

## 使用

```bash
mkdir -p ~/bin
git clone git@github.com:jwu/install-arch.git ~/bin/install-arch
cd ~/bin/install-arch
./install.sh
```

只需要这一个 clone；其余三个仓库由脚本自己拉取。脚本可重复执行，已存在的 checkout 只做
`git pull --ff-only`，已装好的东西不会重做。

## 它做什么

| 步骤 | 内容 |
| --- | --- |
| `repository: configs` | 缺失则 clone 到 `~/bin/configs`，已存在则 pull |
| `repository: desktop-settings` | 同上，提供 Fcitx5/Rime 配置 |
| `repository: pi-config` | 同上，提供 pi 资源 |
| `yay (AUR helper for xwayland-satellite-git)` | 检测 `yay`，缺失时装 `base-devel`，再从 AUR 构建 `yay-bin`（预编译二进制，不需要 Go/Rust 工具链）。必须在 `configs` 之前，否则 `xwayland-satellite-git` 那一步会直接跳过 |
| `configs: packages, waybar module, config sync` | 运行 `configs/linux/install.sh`：pacman 包、Oh My Zsh、从 fork 构建 Waybar niri-windows 模块、编译 gpu-watch、同步全部配置 |
| `verify: Chinese input` | 检查 `fcitx5`、`~/.config/fcitx5/profile` 和 `~/.local/share/fcitx5/rime/rime_ice.schema.yaml`，缺失就记进失败清单（词库下载在 `config.sh` 里是软失败，`fcitx5` 缺失时整个同步也会被静默跳过） |
| `pi CLI` | 检测 `pi`，缺失时先装 `nodejs` + `npm`（Arch 把 npm 拆成了独立包），再用 `npm -g` 安装 `@earendil-works/pi-coding-agent` |
| `pi-config: deploy ~/.pi/agent` | 运行 `pi-config/install.sh` |

**中文输入法（Fcitx5/Rime）随 `configs` 这一步自动同步**：`configs/linux/config.sh` 会在
`fcitx5` 已安装、且 `desktop-settings` 就在相邻目录时调用
`desktop-settings/fcitx5/install-linux.sh`，同步 `profile`、候选窗主题和 Rime 的
`default.custom.yaml` / `rime_ice.custom.yaml`，并在雾凇拼音词库缺失时下载解压（约 16 MB，
不清空用户目录）。所以无论走本脚本还是只跑 `config.sh`，中文输入法都不会再被漏掉。

## 失败处理

- 每个步骤独立执行，失败只记录、不中断后续步骤。
- 末尾打印失败清单，并以非零退出码结束。
- 因此即使 GitHub 不可达、Waybar 模块或 gpu-watch 构建失败，配置同步仍会照常完成。

典型的失败提示与处理：

| 失败步骤 | 处理 |
| --- | --- |
| `configs: packages, …` 中的 `pacman packages` | 出现 `failed retrieving file … 404` 说明 `pacman -Syu` 的 `-y` 拉回的 DB 来自 **mirrorlist 里排第一的那个镜像**，而那份 DB 落后了几小时：它仍旧写着旧版本号（`fcitx5-5.1.22`），旧文件却已被所有镜像删掉，于是 pacman 照着一个不存在的文件名下载。pacman 事务是原子的，**这笔事务里的包一个都不会装上**。修法是**先换镜像、再刷新**，顺序反了没用：`sudo reflector --country China --age 6 --protocol https --latest 20 --sort rate --save /etc/pacman.d/mirrorlist`（`--age 6` 会滤掉落后镜像），或手动把 aliyun 挪下去/注释掉；然后 `sudo pacman -Syy`，用 `pacman -Si fcitx5` 确认已是 `5.1.23-1` 再重跑 |
| `default shell (zsh)` 报 `chsh: shell must be a full path name` | zsh 没装上（根因通常就是上一行的 `pacman packages`），脚本把空路径传给了 `chsh -s`。装好 zsh 后重跑即可 |
| `waybar niri-windows module` | 模块从 `jwu/waybar-niri-windows` 的 main HEAD 构建，直连不通时挂代理重跑：`https_proxy=http://127.0.0.1:7890 ./install.sh`。旧的 `.so` 会保留。详见 `configs/docs/waybar.md` |
| `yay (AUR helper for xwayland-satellite-git)` | 从 AUR 构建 `yay-bin` 失败，常见原因是网络不通，或脚本被 `sudo` 跑（`makepkg` 拒绝 root）。手动补：`sudo pacman -S --needed base-devel git`，再 `git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si`（`makepkg` 本身不能加 sudo） |
| `xwayland-satellite-git (AUR)` | 需要 `yay` 从 AUR 构建，编译依赖 Rust + clang（`yay` 会自己装）。`yay` 缺失时上一行会自动 bootstrap；只有那一步也失败才需要手动补，详见 `configs/docs/xwayland-satellite.md` |
| `Oh My Zsh` / `zsh-autosuggestions` | 网络问题，重跑即可 |
| `verify: Chinese input` | `fcitx5` 没装上（看 `configs: …` 那步的 pacman 输出）、profile 未同步，或 Rime Ice 词库没下下来（网络问题，重跑 `desktop-settings/fcitx5/install-linux.sh` 即可） |
| `configs: …` 中的某个子步骤 | `configs/linux/install.sh` 自己也会逐项汇总，按它的清单处理 |

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `BIN_DIR` | `$HOME/bin` | 三个仓库 clone 的目标目录 |
| `GIT_SSH_BASE` | `git@github.com:jwu` | SSH clone 前缀，私有仓库需要 SSH key |
| `GIT_HTTPS_BASE` | `https://github.com/jwu` | SSH 失败时的回退前缀 |
| `DESKTOP_SETTINGS_DIR` | `$ROOT_DIR/../desktop-settings` | 供 `configs/linux/config.sh` 定位 Fcitx5 配置 |

## 需要手动完成的收尾

- 重新登录一次，`~/.config/environment.d/fcitx5.conf` 里的输入法环境变量才会生效。
- 重启 Waybar 以加载新构建的 CFFI 模块（脚本会打印命令）。
- Rime Ice 词库由 `desktop-settings/fcitx5/install-linux.sh` 在首次运行时下载（约 16 MB）；`build/`、用户词频与 Fcitx5 键盘缓存仍不由脚本管理。

## 验证

```bash
bash -n install.sh
```
