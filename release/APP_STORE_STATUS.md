# ドルトン時間割 — 公開準備の状況

確認日: 2026年10月19日（日本時間）

## 登録情報

- アプリ名: ドルトン時間割
- Bundle ID: `com.yukiyamamoto.jikanwari`
- Siri拡張: `com.yukiyamamoto.jikanwari.intents`
- Widget拡張: `com.yukiyamamoto.jikanwari.widget`
- App Group: `group.com.yukiyamamoto.jikanwari`
- バージョン: 1.0 / TestFlightビルド4（App Storeへ提出済みなのはビルド3）
- 価格: 無料（基準地域Japan / ¥0.00を登録・保存済み）
- サポート: yukifpv1250@gmail.com
- App Store Connect: https://appstoreconnect.apple.com/apps/6824346982/distribution
- Apple側で確認できた状態: ビルド3のApp Store・TestFlight外部ベータともWaiting for Review（2026-10-19再申請）。
- **旧申請を取り下げ、修正版ビルド3でApp Store・TestFlightへ再申請済み。承認・公開は未完了。**

## 実装・検証済み

- アプリ・拡張の表示名とBundle ID、App Groupを更新。
- AI送信の直前に、資料・ファイル名・補足の送信先（Cloudflare / Anthropic）と目的を明示し、送信ごとの明示的同意を追加。
- アプリ内にプライバシーポリシーと問い合わせ先を追加。
- アプリ本体とSiri拡張にUserDefaults使用理由のPrivacyInfo.xcprivacyを追加し、アーカイブ内への同梱を確認。
- 外部AIに送信する任意の写真・文書に関するデータ利用をマニフェストに記載。ストアのプライバシーラベルは別途入力が必要。
- ファイル読み込みを5MB未満に制限し、巨大ファイルを全量メモリへ読み込まないよう変更。
- APIサーバーで実受信サイズ8MiB、指定モデル、出力16,000トークン、入力20,000トークンの制限を追加。
- 入力サイズを推論前のトークン数確認で検査し、検査に失敗した場合は推論を開始しない。
- APIの短時間制限（接続元ごと2回/60秒）、UTC日次上限（接続元10回、全体100回）を追加。日次上限は永続化し、並行リクエストと再起動による回避をテスト。
- 日次キーは接続元IPを日ごとにハッシュ化して生成。カウンタは通常約2日後に稼働ストレージから削除。Cloudflare側のバックアップ・ログ保持は同社のポリシーに従う。
- 上流APIの認証情報をクライアントへ返さず、上流エラーの詳細を一般メッセージに置換。
- Workerの13件のセキュリティ・永続化テスト、ソースとテストの型チェック、デプロイドライランが成功。
- iOSシミュレーター用Releaseビルド、および実機用署名付きReleaseアーカイブの作成が成功。
- アーカイブ内の本体・Widget・Siri拡張のBundle ID、表示名、バージョンを確認。
- ExtensionKitの配置警告は残るが、アーカイブ実体では `Jikanwari.app/Extensions/JikanwariIntents.appex` に配置されていることを確認。Apple側のアップロード検証は未実施。

## 本番API反映

Worker: `jikanwari-reader`

- 本番バージョンID: `00461101-3b56-438e-8837-410cc2055df7`
- プライバシー: https://jikanwari-reader.telsa-gptvoice-worker.workers.dev/privacy
- サポート: https://jikanwari-reader.telsa-gptvoice-worker.workers.dev/support
- 両ページのHTTP 200と問い合わせ先を確認。
- 認証なしの読み取りリクエストは401となることを確認。
- 合成データのみを使う構造化出力の本番テストはHTTP 200で完了し、SSEの最終イベントとJSON出力を確認。
- 既存のANTHROPIC_API_KEYとAPP_TOKENを維持。秘密値は本書に記載しない。

## セキュリティ上の残事項

- 共通のAPP_TOKENはアプリから抽出できるため、正規アプリだけからの利用を証明するものではない。利用回数・入出力制限で濫用と費用を抑えているが、App Attest等による端末検証は未実装。攻撃者による無料枠の消費・サービス妨害を完全には防げない。
- 既存WorkerにはAPIキーのような文字列を名前に使った未使用シークレット設定が2件存在する。コードから参照されていない。文字列は本書に転載しない。設定の削除と、それらが実際に有効なキーであれば発行元での失効を確認する必要がある。現在の本番キー自体が流出したことは確認していない。
- 静的コード確認・テストはセキュリティの完全な保証やAppleの審査合格を意味しない。

## App Store Connect / Xcodeの進捗

- アプリ情報、説明、キーワード、サポートURL、著作権表記、審査連絡先を入力・保存済み。
- 日本語、教育カテゴリ、年齢区分4+を設定済み。
- 日本のみを選択し、配信地域1件を確認。価格はJapan基準0円、保存済み。
- Apple Silicon MacとVision Proへの追加配信をオフにして保存済み。
- プライバシーポリシーURL、5種類のデータ利用を申告。法的な正確性の同意はユーザーから取得後、公開済み表示を確認。
- OSのHTTPS暗号化のみを利用するため非免除暗号化なしとInfo.plistに申告。
- 元のXcode 27ベータでAppleのSDK検証に失敗したため、App Storeから正式版27.1 (27A9275)へ更新。
- 正式版で実機Releaseアーカイブ・Simulator Releaseの両ビルドが成功。
- 新規アーカイブはXcode OrganizerのApple検証に合格、App Store Connectへアップロード完了表示を確認。

## 初回登録対応（ユーザー指定によるビルド2の変更）

- 学校の初期時間割・先生名・教室データをソースから削除。初回と時間割削除後は空のオンボーディング。
- 「自分で入力する」「写真・PDFから読み込む」を用意。手入力は外部APIを使わず、曜日・時刻・科目・教室等を登録できる。
- 登録前の通知許可要求を抑止し、Siriは時間割登録を案内する。
- 個人制作の非公式アプリであることを初回画面、ストア説明、審査メモ、サポートページに明記。
- iPhoneと13インチiPadで、初回表示→手入力→保存→授業表示を実操作で確認。iPhoneではメモを入力して保存後の本文表示も確認。
- iPhone・iPadそれぞれ実画面2枚を撮影し登録。架空の科目と教室だけを入力し、学校の個人情報を含めていない。
- ビルド2のSimulator Releaseと署名付き実機アーカイブ作成が成功。Appleへのアップロードと処理が完了し、v1.0にビルド2を紐付け。
- Xcode更新後のAppleアカウント再ログインはユーザーが完了。

## 審査申請と残作業

- 2026年10月19日11:32（日本時間）にSubmit for Reviewを実行。
- Apple側の「1 Item Submitted」「1.0 Waiting for Review」を確認。
- 提出: https://appstoreconnect.apple.com/apps/6824346982/distribution/reviewsubmissions/details/97638790-8908-44be-ad93-4f692c4365c4
- 無料・日本のみ・承認後の自動公開を設定済み。Apple Silicon MacとVision Proは追加配信しない。
- プライバシー申告公開の同意はユーザーから得て実行済み。Content Rightsは同梱第三者コンテンツなしとして保存。
- このチャットに毎時の継続確認を作成済み（automationId: automation）。状態変化・対応事項・公開時のみ通知する。
- Appleの審査・承認を待つ。指摘があれば調査・修正・再申請し、日本のApp Storeで公開されたことを確認する。
- 上記のセキュリティ残事項（抽出可能な共通トークン、過去の未使用シークレット名）は引き続き区別して追跡。完全にリスクなしと評価していない。

## 保存物

- アーカイブ: `build/archives/DaltonJikanwari-Onboarding-b2.xcarchive`
- 書き出し設定: `build/AppStoreExportOptions.plist`
- Workerテスト: `worker/test/security.test.ts`
- ストア説明の下書き: `release/STORE_METADATA_ja.md`

- 掲載画像: `release/screenshots/`

## TestFlight（追加依頼）

- 2026年10月19日、外部グループ「公開ベータテスト」を作成し、バージョン1.0・ビルド2をベータ審査へ申請。
- Apple側でExternal Group / 1 Build / Waiting for Reviewを確認。
- 公開リンクをOpen to Anyoneで作成: https://testflight.apple.com/join/ujHJ6ReW
- 現時点では承認済みビルドがないため参加不可。管理画面の「Testers cannot join public link until this group has an approved build」と、公開ページの受付停止表示を確認。
- グループ: https://appstoreconnect.apple.com/teams/5a1e8923-86dd-40c3-8bea-dd491487dba8/apps/6824346982/testflight/groups/d6b4d099-19de-4aed-8c1d-762d54ee9695
- ベータ説明、フィードバック先、Apple審査連絡先、テスト項目を登録。サインイン不要。Automatically notify testers有効。
- 外部グループ作成前提として内部グループ「開発者テスト」を作成したが、旧ビルド1の自動配信を避けるため自動配信は無効、テスター・ビルド未追加。第三者への個別招待は行っていない。
- 既存の毎時の継続確認にTestFlight審査と公開リンクでの参加可否も追加。App StoreとTestFlight両方の公開確認後に停止する。

## 継続確認ログ

- 2026-10-19 12:36 JST: App Storeバージョン1.0・提出詳細ともWaiting for Review。審査詳細に新たな指摘・メッセージなし。TestFlightビルド2もWaiting for Review。公開ベータの管理画面は承認済みビルドがないためリンク参加不可のまま。対応事項・状態変化なし。毎時確認を継続。
- 2026-10-19 13:44 JST: App Storeのバージョン1.0・提出詳細、TestFlightビルド2ともWaiting for Reviewを再確認。新しい審査指摘なし。公開リンクは承認済みビルドがないため参加不可のまま。状態変化・対応事項なし。継続確認は有効のまま。
- 2026-10-19: ユーザーの「定期タスク止めて」により、審査・公開確認の定期タスク（automation）をPAUSEDへ変更。以後の定期確認を停止。

## 修正版ビルド3への差し替え（2026-10-19）

- ユーザーから旧申請の取り下げと修正版の再申請を依頼された。App Store旧申請をCancel SubmissionしDeveloper Rejectedを確認。その後編集保存によりPrepare for Submissionへ移行。
- TestFlightビルド2のRemove from Reviewを実行し、ボタンがExpire Buildへ変わったことを確認。旧ビルドを新たに配信しない。
- ユーザーは「時間割・教室データは許可済みなので同梱する」と明示。Content Rightsを第三者コンテンツあり・必要な権利ありへ更新しSavedを確認。個人制作・非公式を維持。
- ユーザー指示により年間予定表は同梱JSONから完全に除去し、自動適用も削除。任意の写真・PDF・テキスト添付から読み取る追加機能へ変更。
- 年間予定は送信ごとに外部AI利用への同意を確認し、日付・休校・振替曜日・最終時限の確認・修正・削除後に保存。年度不明時は推測せず、午前授業の時限も未記載なら未設定。同じ日付を上書きして既存予定とマージ。登録済み予定を設定から編集・削除可能。
- LG・科目選択をやり直しても、ユーザーが追加した年間予定を保持。
- CURRENT_PROJECT_VERSIONを3へ変更し全3ターゲットに適用。Simulator Releaseビルドと署名付き実機アーカイブ成功。
- アーカイブ: build/archives/DaltonJikanwari-b3.xcarchive。Xcode Organizerで1.0 (3) uploaded / Uploaded to Apple / Today at 15:56を確認。
- API側の13件の既存テスト、型チェック、デプロイドライランが成功。年間予定の正常値と不正日付・曜日・最終時限の検証も成功。
- 本番APIで架空の2026年度予定表を読み取り、休校・月曜振替・4限まで・翌年1月の予定・不明時限が未設定となることを確認。個人情報や実際の学校年間予定は送信していない。
- 本番サポート・プライバシーを新機能に合わせて更新。Workerバージョン6ce18b3b-39a9-4a65-9af9-c39c359ee684。公開ページの新しい文言とHTTP成功を確認。
- iPhoneでLG選択→履修科目→生成→保存→授業表示、月カレンダー、任意の年間予定添付画面を確認。iPadでも新画面・初回案内を確認。
- 新掲載画像はrelease/screenshots/b3/。必要サイズのiPhone1206×2622、iPad2048×2732をそれぞれ2枚登録。別の大型iPhone撮影画像は検証用のみ。
- 説明文と審査メモはLG・科目選択、許可済み時間割の同梱、年間予定表の非同梱と任意添付、AI同意の実装に合わせて保存済み。
- 定期確認automationはPAUSEDのまま。自動再開しない。

- 2026-10-19 16:03 JST: ビルド3をApp Storeバージョン1.0に紐付け、Add for Review→Submit for Reviewを実行。「1 Item Submitted」を確認。
- 新しいApp Store提出: https://appstoreconnect.apple.com/apps/6824346982/distribution/reviewsubmissions/details/a8edf6c9-d6ec-4938-ac78-daf1e76e3a24
- TestFlight旧ビルド2を公開ベータグループから取り除き、Build 1.0 (2) has been removedを確認。ビルド3を同グループへ追加し、LG・履修科目・年間予定添付等のテスト内容を入力してSubmit for Review。「External Group ∙ 0 Testers ∙ 1 Build」「Build 1.0 (3)」「Waiting for Review」を確認。
- TestFlightビルド3 ID: 8a921116-fbf6-4fcb-b5b5-20222f2ab808。公開参加リンクは以前と同じ https://testflight.apple.com/join/ujHJ6ReW 。承認前のため参加開始は未確認。

- 最終確認: App Storeのバージョン1.0がWaiting for Review、紐付けBuild 3、Automatically release this versionが選択済み。TestFlightビルド3もWaiting for Review。ベータ共通説明・Review Notes・Privacy Policy URLを修正版向けに更新しSavedを確認。
- App StoreとTestFlightの承認・一般公開は未完了。ユーザーの停止依頼に従い継続確認タスクはPAUSEDのまま。再開・別の定期タスク作成は行っていない。

## TestFlight更新（2026-10-22、ビルド4）

- ユーザーから、App Store公開は保留して現在の修正内容をTestFlightへ更新するよう依頼。
- 現在のSources・Widget・Shared・Intentsとproject.ymlを使いXcodeGenを再生成。CURRENT_PROJECT_VERSIONを全3ターゲットで4へ更新。
- 署名付きReleaseアーカイブ成功: build/archives/DaltonJikanwari-b4.xcarchive。
- アーカイブ内の本体・Widget・Siri拡張がすべてバージョン1.0 / ビルド4であることを確認。
- Xcode OrganizerからApp Store Connectへのアップロードを開始。App Store版のビルド差し替え・審査申請・審査メッセージへの返信は行わない。
- ブラウザのAppleログインはユーザーが再認証を完了。
- 既存TestFlightビルド3はTestingとなっていることを確認。公開ベータグループへビルド4を追加予定。
- 今回の作業ではシミュレーターを起動していない。実機での機能検証済みとは記載しない。

- Xcode Organizerで「Jikanwari 1.0 (4) uploaded」「App upload complete」を確認。AppleのBuild UploadsでもVersion 1.0, Build (4)がComplete（2026-10-22 11:42 JST）となった。
- ユーザーが追加した外部グループ「ドルトン時間割」（3テスター、既存ビルド3）も確認。グループID e14096c5-2c33-4b47-9705-c5218855ccd0、参加リンク https://testflight.apple.com/join/nnf6Jbup 。既存「公開ベータテスト」と両グループへのビルド4追加を進める。

- ビルド4のTestFlight ID: 02050144-87e0-463d-9591-3ddac8a70fcb。
- 「ドルトン時間割」グループからビルド4を選択し、release/TESTFLIGHT_BUILD4_ja.txtの内容をWhat to Testへ入力。Automatically notify testersを有効のまま、TestFlight外部ベータのSubmit for Reviewを実行（App Store本審査への申請ではない）。

- 更新完了: 「ドルトン時間割」（3テスター）と「公開ベータテスト」の両方でBuild 1.0 (4)がTestingとなった。ビルド4詳細でもGroups (2)と両グループ名を確認。What to Testの保存も確認。
- ビルド4はTestFlightで配信可能。Automatically notify testersを有効にして追加済み。既存ビルド3は利用可能なまま残した。
- 今回App Storeの審査対象の変更・再申請・審査担当者への返信は行っていない。定期タスクも再開していない。
