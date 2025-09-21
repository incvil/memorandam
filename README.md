# memorandam
ソフトウェア開発の雑記帳

```
.
└── git/
    └── pre_commit_dll_version/
```

## git
### pre_commit_dll_version
- gitでexeやdllを管理する場合、バージョンアップだけを認めるpre_commit。
- 日本語ファイルパスを扱う場合、このおまじないが必要。
-- git config --global core.quotepath false
