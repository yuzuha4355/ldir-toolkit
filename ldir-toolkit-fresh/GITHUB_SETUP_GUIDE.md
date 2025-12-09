# GitHub Setup Guide for LDIR-Toolkit

このガイドは、LDIR-Toolkit を GitHub に公開する手順を説明します。

## 📋 前提条件

- GitHub アカウントを持っていること
- Git がインストールされていること
- SSH鍵がGitHubに登録されているか、HTTPSでの認証設定が完了していること

## 🚀 Step 1: GitHubでリポジトリを作成

1. **GitHubにログイン** → https://github.com

2. **新しいリポジトリを作成**
   - 右上の「+」→「New repository」
   - Repository name: `ldir-toolkit`
   - Description: `Linux Disaster & Incident Response Toolkit - Comprehensive forensic data collection for 20+ distributions`
   - Public / Private: `Public`（推奨）
   - **重要**: 「Initialize this repository with」のチェックは全て外す（READMEもLICENSEも追加しない）

3. **「Create repository」をクリック**

## 🔧 Step 2: ローカルリポジトリの準備

### Windows (WSL) の場合

```bash
# WSL環境で実行
cd ~

# GitHub用リポジトリディレクトリをダウンロード（すでにある場合はスキップ）
# 以下のファイルをWSL環境にコピー済みと仮定

# Git初期化
cd ~/ldir-github-repo
git init

# 全ファイルをステージング
git add .

# 初回コミット
git commit -m "feat: initial release v0.2.0 - extended edition with 20+ distribution support"

# GitHubのリモートリポジトリを追加（あなたのGitHubユーザー名に置き換える）
git remote add origin git@github.com:YOUR_USERNAME/ldir-toolkit.git

# または HTTPS の場合
# git remote add origin https://github.com/YOUR_USERNAME/ldir-toolkit.git
```

### Linux デスクトップの場合

```bash
cd /path/to/ldir-github-repo
git init
git add .
git commit -m "feat: initial release v0.2.0 - extended edition with 20+ distribution support"
git remote add origin git@github.com:YOUR_USERNAME/ldir-toolkit.git
```

## 📤 Step 3: GitHubにプッシュ

```bash
# メインブランチの名前を確認・変更（必要に応じて）
git branch -M main

# GitHubにプッシュ
git push -u origin main
```

## 🏷️ Step 4: 最初のリリースを作成

### GitHub Web UI での手順

1. **リポジトリページに移動**
   - https://github.com/YOUR_USERNAME/ldir-toolkit

2. **Releases セクション**
   - 右側の「Releases」→「Create a new release」

3. **リリース情報を入力**
   - Tag version: `v0.2.0`
   - Release title: `v0.2.0 - Extended Edition`
   - Description:
     ```markdown
     ## 🎉 LDIR-Toolkit v0.2.0 - Extended Edition
     
     ### Major Features
     - 🌍 Support for 20+ Linux distributions
     - 🛠️ 10 collection modules (8 core + 2 new)
     - ☁️ Cloud metadata collection (AWS/GCP/Azure)
     - 🔧 Custom environment detection (systemd-less, busybox, etc.)
     - 🔐 Evidence integrity (SHA256, manifest, execution log)
     
     ### Supported Distributions
     Ubuntu, Debian, Rocky, AlmaLinux, CentOS, Fedora, Amazon Linux,
     Arch, openSUSE, Gentoo, Alpine, Raspberry Pi OS, Oracle Linux, and more
     
     ### Download
     - **Recommended**: [ldir-toolkit-extended-v0.2.0.tar.gz](#) (21KB)
     - SHA256 hash file included
     - Complete documentation included
     
     ### Quick Start
     ```bash
     tar -xzf ldir-toolkit-extended-v0.2.0.tar.gz
     cd ldir-toolkit-v0.2.0
     sudo ./ldir-collect.sh /tmp/ldir_output
     ```
     
     See [README.md](https://github.com/YOUR_USERNAME/ldir-toolkit#readme) for full documentation.
     ```

4. **配布ファイルをアップロード**
   - 「Attach binaries」から以下をアップロード:
     - `ldir-toolkit-extended-v0.2.0.tar.gz`
     - `ldir-toolkit-extended-v0.2.0.tar.gz.sha256`

5. **「Publish release」をクリック**

## 📝 Step 5: README.md を更新（オプション）

リポジトリのREADME.mdにある `yourusername` を実際のGitHubユーザー名に置き換えます。

```bash
cd ~/ldir-github-repo

# エディタで編集（例: vim, nano）
nano README.md

# または sed で一括置換（YOUR_ACTUAL_USERNAME に置き換える）
sed -i 's/yourusername/YOUR_ACTUAL_USERNAME/g' README.md

# コミット & プッシュ
git add README.md
git commit -m "docs: update GitHub username in README"
git push
```

## 🎨 Step 6: リポジトリ設定のカスタマイズ（オプション）

### Topics（トピック）の追加

リポジトリページ → 「About」の右の歯車アイコン → Topics に以下を追加:
- `linux`
- `forensics`
- `incident-response`
- `security`
- `dfir`
- `bash`
- `sysadmin`
- `cybersecurity`
- `threat-hunting`

### Website（ウェブサイト）
README.mdへのリンクを追加（オプション）

### Social Preview Image
カスタム画像をアップロード（オプション）

## 🔍 Step 7: 確認事項

公開後、以下を確認してください：

- [ ] リポジトリが正しく表示されている
- [ ] README.mdが適切にレンダリングされている
- [ ] LICENSEファイルが認識されている
- [ ] Releasesに v0.2.0 が表示されている
- [ ] ダウンロードリンクが機能している
- [ ] .gitignore が機能している（機密データが含まれていないか確認）

## 🌐 Step 8: 共有

リポジトリURLを共有:
```
https://github.com/YOUR_USERNAME/ldir-toolkit
```

Discord等での投稿例:
```
🎉 LDIR-Toolkit v0.2.0 を GitHub で公開しました！

Linux インシデント対応・フォレンジックツール
- 20種類以上のディストリビューション対応
- クラウド環境メタデータ収集
- 完全オフライン動作可能

🔗 https://github.com/YOUR_USERNAME/ldir-toolkit
📦 Download: https://github.com/YOUR_USERNAME/ldir-toolkit/releases

ぜひお試しください！フィードバックやコントリビューションも歓迎です 🙏
```

## 🔄 今後の更新フロー

```bash
# 変更を加える
cd ~/ldir-github-repo
# ... ファイルを編集 ...

# ステージング & コミット
git add .
git commit -m "feat: add new feature"

# プッシュ
git push

# 新しいバージョンをリリースする場合
# GitHubのWeb UIで新しいReleaseを作成
```

## 🐛 トラブルシューティング

### Q: `git push` で認証エラーが出る
**A**: SSH鍵を設定するか、HTTPSの場合は Personal Access Token を使用してください。
- SSH鍵設定: https://docs.github.com/en/authentication/connecting-to-github-with-ssh
- Personal Access Token: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token

### Q: ファイルサイズが大きすぎる
**A**: GitHubは100MBまでのファイルをサポート。それ以上の場合はGit LFSを使用するか、Releasesで配布してください。

### Q: `.gitignore` が機能しない
**A**: すでにコミット済みのファイルは `.gitignore` の対象外です。以下で削除:
```bash
git rm --cached file_to_ignore
git commit -m "chore: remove ignored file from git"
```

## 📚 参考リンク

- [GitHub Docs - Creating a new repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)
- [GitHub Docs - Managing releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [Git Documentation](https://git-scm.com/doc)

---

以上で GitHub への公開は完了です！🎉
