# Contributing

感谢参与。提交改动前请：

1. 在 Apple silicon MacBook 上验证传感器和手动预览。
2. 运行 `swift build` 和 `./scripts/build-app.sh`。
3. 运行 `.build/debug/MacBookDuo --probe`，确认传感器不可用时应用仍能使用手动预览。
4. 在 Pull Request 中说明 macOS 版本、Mac 型号和是否授予屏幕录制权限。

请不要提交桌面截图、录屏、个人信息、签名证书或密钥。真实桌面帧应只在内存中处理。
