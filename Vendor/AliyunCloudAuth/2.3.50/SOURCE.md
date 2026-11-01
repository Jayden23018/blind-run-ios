# Alibaba CloudAuth iOS SDK source

- Aggregate release: `2.3.50`
- Release date: `2026-07-10`
- Official archive: `https://cn-shanghai-aliyun-cloudauth.oss-cn-shanghai.aliyuncs.com/cloudauth_sdk/2.3.50/iOS-2.3.50-Aliyun.zip`
- Archive MD5: `ef124c58ac90e33ea3d652363cc424fb`
- Archive SHA-256: `a6072c00adf8f533f46ca5de03eb2dd25d8d85e558f0c7d9702b7c731366feca`
- Official release notes: `https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/product-overview/sdk-release-notes`

The SDK binaries are not in this repository. `pod install` runs `scripts/fetch-aliyun-cloudauth.sh`, which downloads the official archive, checks the SHA-256 value, and writes `Frameworks/` and `Resources/` here. Git ignores both directories.

The script installs only the mandatory ID_PRO face-verification subset from the aggregate archive. OCR, NFC, MultiFactor, and beauty modules are intentionally excluded.

To upgrade, change the version and the SHA-256 value in the script, change the `Podfile` path, and read the official release notes first. Never mix binaries from different aggregate releases.
