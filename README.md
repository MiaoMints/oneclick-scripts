# oneclick-scripts

一个专门存放“一键执行 / 一键安装 / 一键检测” Shell 脚本的仓库。

## 当前脚本

- `check_route.sh`：NextTrace 三网回程检测脚本，输出风格参考 `zhanghanyun/backtrace`
- `nexttrace_route_report.md`：示例检测报告

## 使用方式

在 Linux 服务器上直接运行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/MiaoMints/oneclick-scripts/main/check_route.sh)
```

## 说明

- 仓库建议保持公开，方便直接 raw 下载执行
- 脚本会先检查 `nexttrace`，缺失时自动安装
- 输出会先显示 `国家 / 城市 / 服务商 / 项目地址`，再逐条展示三网测试结果

## 后续扩展

以后你可以继续往这个仓库里放其他类似的一键脚本，例如：

- 系统初始化脚本
- 网络检测脚本
- 面板安装脚本
- 运维辅助脚本
