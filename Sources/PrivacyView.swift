import SwiftUI

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("端末に保存する情報") {
                    Text("時間割、追加した年間予定、選択授業の設定、メモは端末内のアプリ領域に保存します。時間割と設定は、Siri拡張が参照できるよう同じApp Group内で共有します。OSのバックアップ対象になる場合があります。")
                }
                Section("AIによる読み取り（任意）") {
                    Text("同意して送信した場合に限り、選択した写真・PDF・テキスト、ファイル名、補足欄の内容を、読み取り処理のためCloudflareの中継サーバー経由でAnthropicのClaude APIに送ります。資料に含まれる氏名、先生名、クラスなども送信対象です。不要な個人情報を除いてからご利用ください。")
                    Text("中継サーバーは資料をアプリのデータベースに保存しません。通信の処理にIPアドレス等が使われます。不正利用防止のため、日ごとに変わるIPアドレス由来のハッシュと利用回数を保存し、通常は約2日後に稼働データから削除します。サービスの稼働確認と障害対応のため、通信時刻・処理状況等の診断情報も扱います。CloudflareおよびAnthropicでのログ・保存期間等は各社のポリシーに従います。AIの出力には誤りがあるため、保存前に確認・修正してください。")
                    Link("Anthropicのプライバシーポリシー", destination: URL(string: "https://www.anthropic.com/legal/privacy")!)
                    Link("Cloudflareのプライバシーポリシー", destination: URL(string: "https://www.cloudflare.com/privacypolicy/")!)
                }
                Section("権限") {
                    Text("カメラは紙の時間割・年間予定表のスキャンに、通知は授業開始のお知らせに使います。写真やファイルはユーザーが選択したものだけを読み込みます。広告やトラッキングの機能はありません。")
                }
                Section("削除") {
                    Text("読み込んだ時間割は設定から削除できます。メモは編集して消せます。端末内のアプリデータはアプリを削除すると削除されます。送信済み資料については各送信先のポリシーをご確認ください。")
                }
                Section("お問い合わせ") {
                    Link("yukifpv1250@gmail.com", destination: URL(string: "mailto:yukifpv1250@gmail.com")!)
                }
            }
            .navigationTitle("プライバシーポリシー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}
