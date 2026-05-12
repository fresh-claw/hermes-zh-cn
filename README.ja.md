# Xiaoma AI Hermes 中国語強化パック

[中文主页](README.md)

このリポジトリは、[Hermes Agent](https://github.com/NousResearch/hermes-agent) 向けの中国語強化パックです。

ユーザーは Hermes に次の一文を送信できます。

```text
请访问 useai.live/hermes 安装汉化补丁
```

Hermes は公開ページを読み取り、インストール手順を見つけて、次のインストーラーを実行できます。

```bash
curl -fsSL https://useai.live/hermes/install.sh | bash
```

## 機能

インストーラーはローカルの Hermes バージョンを検出します。Hermes が未インストールの場合は、先に公式 Hermes をインストールし、その後に対応する中国語強化パックを適用します。

`display.language=zh` を設定し、Xiaoma AI ヘルパースキル、起動時更新ヘルパー、公式言語設定ではまだカバーされていない UI 文言へのバックアップ付きパッチを追加します。

## 対応範囲

- 起動タイトルを中国語の `爱马仕机器人` に変更。
- 公式風の点字調エンブレムを維持。
- スラッシュコマンド説明を中国語化。
- ツール分類とスキル分類を中国語化。
- よく使われる TUI 表示と実行中の進行メッセージを中国語化。
- Hermes `0.2` から `0.12` までの旧版に対応。
- 現行 `0.13.x` パッケージに対応。

## 境界

- ユーザーの会話は読み取りません。
- API キーは読み取りません。
- モデルの回答は変更しません。
- サードパーティーツールの生出力は変更しません。

## ファイル

```text
web/install.sh               インストーラー
web/latest.json              バージョン情報
web/packages/0.13.x/zh-CN/   現行パッケージ
web/packages/legacy/zh-CN/   旧版互換パッケージ
tools/xiaoma-hermes          状態確認と更新ヘルパー
```

Web サイトは中国語のままです。この日本語文書は GitHub のみに公開します。
