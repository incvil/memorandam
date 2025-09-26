# memorandam
ソフトウェア開発の雑記帳

```
.
└── git/
    └── pre_commit_dll_version/
```

## git
### pre_commit_dll_version
Windows 11のgitでexeやdllを管理する場合、バージョンアップだけを認めるpre_commit。
* 使い方
    * pre-commitを.git\hooksへコピーする
* 日本語ファイルパスを扱う場合、事前にこのおまじないが必要。
    * git config --global core.quotepath false
