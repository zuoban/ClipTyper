# ClipTyper

[English](#english) | [简体中文](#简体中文)

---

## 简体中文

ClipTyper 是一款专为 macOS 设计的原生菜单栏工具，它可以模拟用户逐字输入剪贴板中的文本。对于那些禁止直接粘贴的输入框，或者需要模拟真实打字效果的场景，ClipTyper 是您的理想选择。

### 演示

![ClipTyper 演示](docs/assets/demo.gif)

[查看演示视频](docs/assets/demo.mp4)

### 核心功能

*   **模拟逐字输入**：将剪贴板内容模拟为真实的键盘敲击事件。
*   **总时长控制**：您可以设定完成整段文字输入的总时间（毫秒），应用会自动计算打字速度。
*   **随机抖动**：支持配置随机延迟时间，模拟真实的人类打字节奏。
*   **全 Unicode 支持**：完美支持中文、表情符号（Emoji）以及各种特殊字符，不受输入法布局限制。
*   **原生菜单栏交互**：采用现代化的 Popover 悬浮窗设计，操作直观。
*   **全局快捷键**：支持自定义全局触发快捷键（默认为 `Command + Shift + V`）。
*   **跨应用支持**：输入过程中切换应用不影响输入，且支持随时通过快捷键中止。

### 安装要求

*   macOS 14.0 或更高版本。
*   需要授予“辅助功能（Accessibility）”权限。

### 使用说明

1.  **启动应用**：运行 ClipTyper，它会出现在顶部菜单栏。
2.  **授予权限**：首次使用需在“系统设置 -> 隐私与安全性 -> 辅助功能”中允许 ClipTyper。
3.  **配置参数**：点击菜单栏图标，调节“总输入时间”和“随机抖动”。
4.  **触发输入**：复制一段文字，将光标置于目标输入框，按下快捷键（默认 `⌘⇧V`）。
5.  **中止输入**：在输入过程中再次按下快捷键即可停止。

### 隐私与权限

*   ClipTyper 只在您触发快捷键时读取当前剪贴板文本。
*   剪贴板内容仅用于本地模拟输入，不会上传、存储或写入日志。
*   辅助功能权限仅用于向当前系统会话发送键盘事件。

---

## English

ClipTyper is a native macOS menu bar utility that simulates character-by-character typing of your clipboard content. It is perfect for bypassing "paste-disabled" input fields or whenever you need to simulate realistic human typing.

### Demo

![ClipTyper demo](docs/assets/demo.gif)

[Watch the demo video](docs/assets/demo.mp4)

### Key Features

*   **Keystroke Simulation**: Converts clipboard text into real keyboard events.
*   **Total Duration Logic**: Set a target time (in milliseconds) to complete the entire text, and the app calculates the speed automatically.
*   **Typing Jitter**: Adds configurable random variance to simulate human typing rhythms.
*   **Full Unicode Support**: Works perfectly with Chinese, Emojis, and special characters regardless of keyboard layout.
*   **Polished Popover UI**: Modern macOS-native interface accessible directly from the menu bar.
*   **Global Hotkey**: Configurable trigger shortcut (Default: `Command + Shift + V`).
*   **Cross-App Reliability**: Keeps typing even if you switch windows, with an emergency stop feature.

### Requirements

*   macOS 14.0 or later.
*   Accessibility permissions are required to simulate keystrokes.

### How to Use

1.  **Launch**: Run ClipTyper; it lives in your menu bar.
2.  **Permissions**: Grant accessibility access in "System Settings -> Privacy & Security -> Accessibility" on the first run.
3.  **Configure**: Click the menu bar icon to adjust "Total Duration" and "Jitter".
4.  **Trigger**: Copy some text, click your target input field, and press the hotkey (`⌘⇧V`).
5.  **Stop**: Press the hotkey again during typing to cancel the operation.

### Privacy & Permissions

*   ClipTyper reads clipboard text only when you trigger the hotkey.
*   Clipboard content is used locally for simulated typing only. It is not uploaded, stored, or written to logs.
*   Accessibility permission is used only to send keyboard events in the current macOS session.

### Development

This project is built with **SwiftUI** and uses `sindresorhus/KeyboardShortcuts` for hotkey management.

```bash
# Clone the repository
git clone https://github.com/yourusername/ClipTyper.git

# Open in Xcode
open ClipTyper.xcodeproj
```

### Acknowledgments

Thanks to the [Linux.do](https://linux.do/) community for testing, feedback, and discussion.

### License

[MIT License](LICENSE)
