import SwiftUI

/// アプリ全体で共有する寸法・色・しきい値。
/// 画面側にマジックナンバーを書かないための唯一の供給元。
enum DesignTokens {

    // MARK: - しきい値

    static let lowConfidenceThreshold = 0.60

    /// 学習を開始できる目安の枚数。Dataset画面の進捗表示に使う。
    static let trainingReadyImageCount = 60

    /// 1金種あたり最低限ほしいインスタンス数。
    static let balancedInstanceCountPerClass = 40

    // MARK: - 余白

    enum Spacing {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 4
        static let compact: CGFloat = 8
        static let regular: CGFloat = 12
        static let comfortable: CGFloat = 16
        static let loose: CGFloat = 24
        static let section: CGFloat = 32
    }

    // MARK: - 角丸

    static let compactCornerRadius: CGFloat = 8
    static let regularCornerRadius: CGFloat = 12

    // MARK: - サイズ

    static let minimumTapSize: CGFloat = 44
    static let overlayLineWidth: CGFloat = 2
    static let selectedOverlayLineWidth: CGFloat = 3
    static let resizeHandleSize: CGFloat = 20
    static let statusDotSize: CGFloat = 8
    static let meterHeight: CGFloat = 6
    static let thumbnailGridSpacing: CGFloat = 2
    static let thumbnailMinimumWidth: CGFloat = 112

    // MARK: - Annotation viewport

    static let minimumAnnotationZoom: CGFloat = 1
    static let maximumAnnotationZoom: CGFloat = 6
    static let annotationZoomStep: CGFloat = 0.5

    // MARK: - モーション

    static let hintVisibleDuration: Duration = .seconds(4)
}

// MARK: - セマンティックカラー

extension Color {
    /// 正常・完了。
    static let mtSuccess = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.83, blue: 0.55, alpha: 1)
            : UIColor(red: 0.10, green: 0.55, blue: 0.31, alpha: 1)
    })

    /// 要確認・注意。
    static let mtWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.70, blue: 0.24, alpha: 1)
            : UIColor(red: 0.72, green: 0.44, blue: 0.02, alpha: 1)
    })

    /// エラー・失敗。
    static let mtDanger = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.45, blue: 0.42, alpha: 1)
            : UIColor(red: 0.77, green: 0.16, blue: 0.13, alpha: 1)
    })

    /// 進行中・情報。
    static let mtAccent = Color.accentColor

    /// 待機・未着手。
    static let mtIdle = Color.secondary

    /// カメラ・キャンバスの下地。
    static let mtCanvas = Color.black

    /// 画面を面で区切るための薄い塗り。カード（枠 + 影）の代替。
    static let mtSurface = Color(uiColor: .secondarySystemBackground)
}

// MARK: - 硬貨のビジュアル同一性

extension CoinDenomination {
    /// 実際の硬貨の直径 (mm)。チップの大きさに反映して誤選択を減らす。
    var diameterMillimeters: Double {
        switch self {
        case .one: 20.0
        case .five: 22.0
        case .ten: 23.5
        case .fifty: 21.0
        case .oneHundred: 22.6
        case .fiveHundred: 26.5
        }
    }

    /// 実物の素材に寄せた色。金種の識別を数字だけに頼らせない。
    var tint: Color {
        switch self {
        case .one:
            Color(uiColor: UIColor(red: 0.78, green: 0.79, blue: 0.81, alpha: 1))
        case .five:
            Color(uiColor: UIColor(red: 0.80, green: 0.66, blue: 0.30, alpha: 1))
        case .ten:
            Color(uiColor: UIColor(red: 0.75, green: 0.47, blue: 0.30, alpha: 1))
        case .fifty:
            Color(uiColor: UIColor(red: 0.68, green: 0.71, blue: 0.74, alpha: 1))
        case .oneHundred:
            Color(uiColor: UIColor(red: 0.60, green: 0.64, blue: 0.68, alpha: 1))
        case .fiveHundred:
            Color(uiColor: UIColor(red: 0.85, green: 0.72, blue: 0.38, alpha: 1))
        }
    }

    /// 5円・50円は穴あき。チップ上でも穴を描いて区別する。
    var hasCenterHole: Bool {
        self == .five || self == .fifty
    }

    /// 直径をチップの表示サイズへ写像する。
    func chipDiameter(minimum: CGFloat = 34, maximum: CGFloat = 46) -> CGFloat {
        let smallest = CoinDenomination.one.diameterMillimeters
        let largest = CoinDenomination.fiveHundred.diameterMillimeters
        let ratio = (diameterMillimeters - smallest) / (largest - smallest)
        return minimum + (maximum - minimum) * ratio
    }
}
