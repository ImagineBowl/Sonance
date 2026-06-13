//
//  TunerLayout.swift
//  Sonance
//
//  Created by Ahsan Minhas on 02/06/2026.
//

import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum TunerLayout {
    struct GaugeMetrics {
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
    }

    #if os(iOS)
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    #else
    static var isPad: Bool { false }
    #endif

    static var noteTopPadding: CGFloat { isPad ? 72 : 50 }
    static var noteBottomPadding: CGFloat { isPad ? 96 : 50 }
    static var contentSpacing: CGFloat { isPad ? 28 : 16 }

    static func gaugeMetrics(containerWidth: CGFloat, containerHeight: CGFloat) -> GaugeMetrics {
        let width = if isPad {
            min(containerWidth * 0.52, 400)
        } else {
            containerWidth * 0.8
        }

        let height = if isPad {
            min(containerHeight * 0.18, 200)
        } else {
            containerHeight * 0.3
        }

        let radius = width * 0.4375
        return GaugeMetrics(width: width, height: height, radius: radius)
    }
}
