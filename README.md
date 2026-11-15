# LocalTranslator — Phase 3（音声認識）

Windows 11 から GitHub に push すると、GitHub Actions の macOS 環境で iPhone 用の SwiftUI アプリをビルドし、署名なし IPA を作ります。

アプリは対面翻訳の画面です。上半分が相手用（向かいの人が読めるよう逆さま表示）、下半分が自分用で、真ん中の帯をタップすると相手の言語（韓国語・中国語・英語）を切り替えられます。帯の左右のボタンで、訳文と自分の発言の文字サイズを一緒に小・中・大の 3 段階で変えられます。文が枠に入りきらないときは、枠の中をスクロールして読めます。

マイクボタンを 1 回押すと録音が始まり、もう 1 回押すと止まって、SenseVoice（sherpa-onnx）が声を文字にします。自分のマイクは日本語、相手のマイクは帯で選んだ言語で聞き取ります。翻訳（PLaMo 3 Translate）はまだつないでいないので、今は聞き取った文がそのまま両方のパネルに出ます。

## 音声認識のしくみ

- エンジン：[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)（Apache-2.0）。`project.yml` で Swift Package として v2.0.1 を指定し、ビルドのときに Xcode が取ってきます。
- モデル：`sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17`（約 230MB）。リポジトリには入れず、GitHub Actions がビルドの前にダウンロードして `Models/` に置き、アプリの中に入れます。2 回目からはキャッシュを使います。
- 録音した音は 16kHz・モノラルに変換して、iPhone の中だけで文字にします。外部には送信しません。

## ファイルの役割

| ファイル | 役割 |
| --- | --- |
| [`LocalTranslator/LocalTranslatorApp.swift`](LocalTranslator/LocalTranslatorApp.swift) | アプリの起動場所です。 |
| [`LocalTranslator/ContentView.swift`](LocalTranslator/ContentView.swift) | 上下 2 分割の対面翻訳画面と、マイクボタンを押したときの動き（録音 → 文字にする）です。 |
| [`LocalTranslator/AudioRecorder.swift`](LocalTranslator/AudioRecorder.swift) | マイクの許可と録音です。音を 16kHz・モノラルに変換してためます。 |
| [`LocalTranslator/SpeechRecognizer.swift`](LocalTranslator/SpeechRecognizer.swift) | SenseVoice のモデルを読み込んで、録った音を文字にします。 |
| [`LocalTranslator/PartnerLanguage.swift`](LocalTranslator/PartnerLanguage.swift) | 相手の言語の一覧と、SenseVoice・PLaMo に渡す言語コード、相手側パネルの案内文です。 |
| [`LocalTranslator/TextSize.swift`](LocalTranslator/TextSize.swift) | 文字サイズの 3 段階（小・中・大）です。訳文と自分の発言は同じ大きさです。 |
| [`project.yml`](project.yml) | XcodeGen が Xcode プロジェクトを作るための設定です。最低対応バージョンは iOS 17.0 で、画面は縦向き固定です。sherpa-onnx の指定と、マイクを使う理由の説明文もここにあります。 |
| [`.github/workflows/build.yml`](.github/workflows/build.yml) | macOS 上でモデルのダウンロード、プロジェクト生成、実機向けビルド、IPA の作成とアップロードを行います。 |
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
- モデルが入っているので、IPA は約 250MB あります。
- 初めてマイクを押すと、マイクを使ってよいか iPhone が聞いてきます。「許可」を選んでください。
- CI の成功は IPA を生成できたことを示します。iPhone 12 mini でのインストールと画面表示は、署名後に実機で確認します。この IPA は App Store や TestFlight に提出できません。
