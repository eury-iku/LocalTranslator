# LocalTranslator — Phase 1

Windows 11 から GitHub に push すると、GitHub Actions の macOS 環境で iPhone 用の SwiftUI アプリをビルドし、署名なし IPA を作ります。アプリを起動すると `Hello, World!` が表示されます。翻訳と音声認識は今後のフェーズで追加します。

## ファイルの役割

| ファイル | 役割 |
| --- | --- |
| [`LocalTranslator/LocalTranslatorApp.swift`](LocalTranslator/LocalTranslatorApp.swift) | アプリの起動場所と Hello World の画面を定義します。 |
| [`project.yml`](project.yml) | XcodeGen が Xcode プロジェクトを作るための設定です。最低対応バージョンは iOS 17.0 です。 |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | macOS 上でプロジェクト生成、実機向けビルド、IPA の作成とアップロードを行います。 |
| [`.gitignore`](.gitignore) | 生成された Xcode プロジェクト、ビルド成果物、署名用ファイルなどを Git の管理対象から外します。 |

## 1. Windows から GitHub へ送る

Git for Windows を用意し、GitHub に空の公開リポジトリを作ります。すでに空のリポジトリがあれば、そのリポジトリを使えます。新規作成時は README、`.gitignore`、ライセンスの自動追加をオフにします。[GitHub の手順](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)

この README があるフォルダで PowerShell を開き、以下を上から順に実行します。

1. `git init -b main` で、このフォルダを Git の管理下に置きます。
2. `git add -- .gitignore README.md project.yml LocalTranslator/LocalTranslatorApp.swift .github/workflows/build.yml` で、公開する 5 ファイルを選びます。
3. `git commit -m "Add Phase 1 iOS build"` で、選んだファイルを Git に記録します。
4. `git remote add origin '<リポジトリのHTTPS URL>'` で、送信先を登録します。山括弧ごと、GitHub が表示した HTTPS URL に置き換えます。
5. `git push -u origin main` で GitHub に送ります。必要に応じて、表示された案内に沿って GitHub にログインします。

すでにこのフォルダで Git を使っている場合は手順 1 を省きます。送信先の `origin` が登録済みなら、接続先を確認して手順 4 を省きます。

## 2. IPA をダウンロードする

1. GitHub にログインし、リポジトリの **Actions** を開きます。
2. **Build unsigned iOS IPA** を選び、最新の実行が緑のチェックになったら開きます。初回 push 後は **Run workflow** から手動でも実行できます。
3. **Artifacts** にある **LocalTranslator-unsigned** をダウンロードします。ダウンロードした ZIP を展開すると `LocalTranslator-unsigned.ipa` が入っています。[GitHub の成果物ダウンロード手順](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## 3. 署名なし IPA の制約

- IPA は `Payload/LocalTranslator.app` を入れた ZIP 形式のファイルです。CI では開発者証明書とプロビジョニングプロファイルを使わずに作ります。[Apple の署名要件](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web)
- **署名なしのままでは iPhone にインストールできません。** 実機で試すには、Windows の Sideloadly で展開した `.ipa` を選び、Apple Account（Apple ID）で開発用に署名してインストールします。iPhone 側ではデベロッパモードを有効にします。無料アカウントで署名したアプリの有効期間は 7 日で、期限後も使うには再署名が必要です。[デベロッパモード](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)・[Sideloadly 公式案内](https://sideloadly.io/)
- CI の成功は IPA を生成できたことを示します。iPhone 12 mini でのインストールと画面表示は、署名後に実機で確認します。この IPA は App Store や TestFlight に提出できません。
